//===- RegisterClearing.cpp --------------------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#include "RegisterClearing.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/iterator_range.h"
#include "llvm/CodeGen/MachineFunction.h"
#include "llvm/CodeGen/MachineInstr.h"
#include "llvm/CodeGen/MachineInstrBuilder.h"
#include "llvm/CodeGen/MachineOperand.h"
#include "llvm/CodeGen/MachineRegisterInfo.h"
#include "llvm/CodeGen/TargetFrameLowering.h"
#include "llvm/CodeGen/TargetInstrInfo.h"
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
      if (!MO.isReg() || !MO.getReg())
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

/// Keep allocatable physical defs, including target scratch, live through the
/// clearing sequence using the exit or a target-requested FAKE_USE.
static MachineInstr *
keepClearedRegsLive(iterator_range<MachineBasicBlock::iterator> Sequence,
                    MachineInstr &ExitMI, const TargetRegisterInfo &TRI,
                    const TargetFrameLowering &TFI) {
  MachineFunction &MF = *ExitMI.getMF();
  const BitVector Allocatable = TRI.getAllocatableSet(MF);
  const bool UseFakeUse = TFI.useFakeUseForZeroCallUsedRegs(ExitMI);
  MachineInstr *UseMI = &ExitMI;

  // Subregister uses keep only part of a wider def live; undef keeps none.
  BitVector ExitUses(TRI.getNumRegs());
  for (const MachineOperand &MO : ExitMI.operands())
    if (MO.isReg() && MO.isUse() && MO.getReg().isPhysical() && !MO.isUndef())
      ExitUses.set(MO.getReg());

  for (MachineInstr &MI : Sequence) {
    for (MachineOperand &MO : MI.operands()) {
      if (!MO.isReg() || !MO.isDef() || !MO.getReg().isPhysical())
        continue;
      MCRegister Reg = MO.getReg().asMCReg();
      if (!Allocatable.test(Reg))
        continue;
      MO.setIsDead(false);
      if (!ExitUses.test(Reg)) {
        if (UseMI == &ExitMI && UseFakeUse) {
          const TargetInstrInfo &TII = *MF.getSubtarget().getInstrInfo();
          UseMI =
              BuildMI(*ExitMI.getParent(), ExitMI.getIterator(),
                      ExitMI.getDebugLoc(), TII.get(TargetOpcode::FAKE_USE));
          MF.setHasFakeUses(true);
        }
        UseMI->addOperand(MF, MachineOperand::CreateReg(Reg, /*isDef=*/false,
                                                        /*isImp=*/true));
        ExitUses.set(Reg);
      }
    }
  }
  return UseMI;
}

bool llvm::emitZeroCallUsedRegsWithScratch(
    BitVector RegsToZero, const BitVector &ScratchRegs, MachineBasicBlock &MBB,
    MachineBasicBlock::iterator &InsertPt, MachineInstr &ExitMI,
    RegScavenger *RS) {
  const MachineFunction &MF = *MBB.getParent();
  const TargetFrameLowering &TFI = *MF.getSubtarget().getFrameLowering();
  const TargetRegisterInfo &TRI = *MF.getSubtarget().getRegisterInfo();
  if (!validateScratchRegs(ScratchRegs, MBB, InsertPt, TFI, TRI))
    return false;
  RegsToZero |= ScratchRegs;

  // Anchor the inserted range to its predecessor; MBB.begin() can change.
  const bool AtBegin = InsertPt == MBB.begin();
  MachineBasicBlock::iterator Before =
      AtBegin ? MBB.end() : std::prev(InsertPt);

  TFI.emitZeroCallUsedRegs(RegsToZero, MBB, InsertPt, RS);

  MachineBasicBlock::iterator First = AtBegin ? MBB.begin() : std::next(Before);
  MachineInstr *UseMI =
      keepClearedRegsLive(make_range(First, InsertPt), ExitMI, TRI, TFI);
  if (UseMI != &ExitMI)
    InsertPt = UseMI->getIterator();
  return true;
}
