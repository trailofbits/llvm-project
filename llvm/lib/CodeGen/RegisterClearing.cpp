//===- RegisterClearing.cpp --------------------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#include "RegisterClearing.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/CodeGen/MachineFunction.h"
#include "llvm/CodeGen/MachineRegisterInfo.h"
#include "llvm/CodeGen/TargetFrameLowering.h"
#include "llvm/CodeGen/TargetRegisterInfo.h"
#include "llvm/CodeGen/TargetSubtargetInfo.h"
#include "llvm/IR/DiagnosticInfo.h"
#include "llvm/IR/Function.h"
#include "llvm/IR/LLVMContext.h"

using namespace llvm;

/// Whether clearing \p Regs would overwrite a value required at the exit.
static bool anyRegNeededAtExit(const BitVector &Regs,
                               const MachineBasicBlock &MBB,
                               MachineBasicBlock::const_iterator InsertPt,
                               const TargetRegisterInfo &TRI) {
  const MachineFunction &MF = *MBB.getParent();

  // Some return pseudos do not name the return-address register explicitly.
  if (MCRegister RAReg = TRI.getRARegister())
    for (MCRegister Reg : TRI.sub_and_superregs_inclusive(RAReg))
      if (Regs.test(Reg.id()))
        return true;

  // Use the finalized list, including custom call-saved registers. These values
  // must survive even when the exit does not name them.
  for (const MCPhysReg *CSRegs = MF.getRegInfo().getCalleeSavedRegs();
       MCPhysReg CSReg = *CSRegs; ++CSRegs)
    for (MCRegister Reg : TRI.sub_and_superregs_inclusive(CSReg))
      if (Regs.test(Reg.id()))
        return true;

  // Preserve registers referenced by instructions after the insertion point.
  for (const MachineInstr &MI : make_range(InsertPt, MBB.end()))
    for (const MachineOperand &MO : MI.operands()) {
      if (!MO.isReg() || !MO.getReg() || (MO.isUse() && MO.isUndef()))
        continue;
      for (MCPhysReg SReg : TRI.sub_and_superregs_inclusive(MO.getReg()))
        if (Regs.test(SReg))
          return true;
    }

  return false;
}

/// Validate the scratch contract before handing the declarations to the target.
static bool validateScratchRegs(const BitVector &Regs,
                                const MachineBasicBlock &MBB,
                                MachineBasicBlock::const_iterator InsertPt,
                                const TargetFrameLowering &TFI,
                                const TargetRegisterInfo &TRI) {
  if (Regs.none())
    return true;

  const MachineFunction &MF = *MBB.getParent();
  auto Diagnose = [&](const Twine &Message) {
    MF.getFunction().getContext().diagnose(DiagnosticInfoUnsupported{
        MF.getFunction(), Message, DiagnosticLocation(), DS_Error});
    return false;
  };

  BitVector Allocatable = TRI.getAllocatableSet(MF);
  for (MCRegister Reg : Regs.set_bits())
    if (!TFI.isZeroCallUsedRegsScratchReg(MF, Reg) || !Allocatable.test(Reg))
      return Diagnose(Twine("register '") + TRI.getName(Reg) +
                      "' is not supported for scratch register clearing");

  if (anyRegNeededAtExit(Regs, MBB, InsertPt, TRI))
    return Diagnose("scratch register clearing would overwrite a register "
                    "needed at the exit");
  return true;
}

bool llvm::emitZeroCallUsedRegsWithScratch(BitVector RegsToZero,
                                           const BitVector &ScratchRegs,
                                           MachineBasicBlock &MBB,
                                           MachineBasicBlock::iterator InsertPt,
                                           RegScavenger *RS) {
  const MachineFunction &MF = *MBB.getParent();
  const TargetFrameLowering &TFI = *MF.getSubtarget().getFrameLowering();
  const TargetRegisterInfo &TRI = *MF.getSubtarget().getRegisterInfo();
  if (!validateScratchRegs(ScratchRegs, MBB, InsertPt, TFI, TRI))
    return false;
  RegsToZero |= ScratchRegs;
  TFI.emitZeroCallUsedRegs(RegsToZero, MBB, InsertPt, RS);
  return true;
}
