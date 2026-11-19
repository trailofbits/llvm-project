//===- AArch64ZeroizationVerifier.cpp - Final register values -------------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#include "AArch64InstrInfo.h"
#include "AArch64Subtarget.h"
#include "AArch64Zeroization.h"
#include "Utils/AArch64BaseInfo.h"
#include "llvm/ADT/BitVector.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/STLFunctionalExtras.h"
#include "llvm/ADT/SetVector.h"
#include "llvm/ADT/StringExtras.h"
#include "llvm/CodeGen/MachineFunction.h"
#include "llvm/CodeGen/MachineInstr.h"
#include "llvm/IR/DiagnosticInfo.h"
#include "llvm/IR/Function.h"
#include "llvm/IR/LLVMContext.h"
#include "llvm/IR/Metadata.h"
#include "llvm/Support/MathExtras.h"

using namespace llvm;

namespace {
// The mask uses architectural X0-X30 and Q0-Q31 encoding numbers. It is
// independent of LLVM's internal register numbering and survives MIR replay.
constexpr StringLiteral ObligationTag = "aarch64.zero-call-used-regs";

uint64_t registerBit(MCRegister Reg, const TargetRegisterInfo &TRI) {
  bool Vector = AArch64::FPR128RegClass.contains(Reg);
  assert((Vector || AArch64::GPR64RegClass.contains(Reg)) &&
         "unexpected width");
  return uint64_t(1) << (TRI.getEncodingValue(Reg) + (Vector ? 32 : 0));
}

bool isObligation(const MachineOperand &MO) {
  if (!MO.isMetadata() || !MO.getMetadata()->getNumOperands())
    return false;
  auto *Tag = dyn_cast_or_null<MDString>(MO.getMetadata()->getOperand(0));
  return Tag && Tag->getString() == ObligationTag;
}

// The plan is trusted compiler input to this final check. Even an empty mask
// can be legitimate when every candidate is reserved, saved or live here.
// Only an absent, malformed or duplicate obligation is an invalid record.
std::optional<uint64_t> requiredRegisters(const MachineInstr &MI) {
  std::optional<uint64_t> Required;
  for (const MachineOperand &MO : MI.operands()) {
    if (!isObligation(MO))
      continue;
    const MDNode *MD = MO.getMetadata();
    if (Required || MD->getNumOperands() != 2)
      return std::nullopt;
    auto *Bits = dyn_cast_or_null<MDString>(MD->getOperand(1));
    uint64_t Mask;
    if (!Bits || Bits->getString().getAsInteger(16, Mask))
      return std::nullopt;
    Required = Mask;
  }
  return Required;
}

// Track the architectural value, not PEI's implicit liveness operands. A system
// register write is identified by its encoded register number and source GPR.
static bool leavesNZCVZero(const MachineInstr &MI, bool WasZero,
                           const TargetRegisterInfo &TRI) {
  if (MI.getOpcode() == AArch64::MSR)
    return MI.getOperand(0).isImm() &&
           MI.getOperand(0).getImm() == AArch64SysReg::NZCV &&
           MI.getOperand(1).isReg() &&
           MI.getOperand(1).getReg() == AArch64::XZR;
  if (MI.isMetaInstruction())
    return WasZero;
  if (MI.isInlineAsm() || MI.isCall() || MI.isPseudo() ||
      MI.hasUnmodeledSideEffects() ||
      MI.getDesc().hasImplicitDefOfPhysReg(AArch64::NZCV, &TRI) ||
      MI.modifiesRegister(AArch64::NZCV, &TRI))
    return false;
  return WasZero;
}

bool isNZCVWrite(const MachineInstr &MI) {
  return MI.getOpcode() == AArch64::MSR && MI.getOperand(0).isImm() &&
         MI.getOperand(0).getImm() == AArch64SysReg::NZCV;
}

// Recognize architectural full-register clears in finalized code. Writing W
// zero-extends into X. A scalar FMOV from XZR clears the upper SIMD bits too.
uint64_t definedZero(const MachineInstr &MI, const TargetRegisterInfo &TRI) {
  bool Vector = false;
  switch (MI.getOpcode()) {
  case AArch64::MOVZWi:
  case AArch64::MOVZXi:
  case AArch64::MOVIv2d_ns:
    if (MI.getOperand(1).getImm() != 0)
      return 0;
    Vector = MI.getOpcode() == AArch64::MOVIv2d_ns;
    break;
  case AArch64::FMOVXDr:
    if (MI.getOperand(1).getReg() != AArch64::XZR)
      return 0;
    [[fallthrough]];
  case AArch64::FMOVD0:
    // emitFMov0 lowers this pseudo to a whole-register zero.
    Vector = true;
    break;
  default:
    return 0;
  }
  unsigned Encoding = TRI.getEncodingValue(MI.getOperand(0).getReg());
  return uint64_t(1) << (Encoding + (Vector ? 32 : 0));
}

uint64_t transferRegisters(const MachineInstr &MI, uint64_t Known,
                           const TargetRegisterInfo &TRI) {
  if (MI.isMetaInstruction())
    return Known;
  // Inline assembly, calls and unmodeled expansions can write architectural
  // state that does not appear among the explicit definitions. NZCV writes
  // and the single late FMOVD0 expansion have known GPR and SIMD effects.
  if (!isNZCVWrite(MI) && MI.getOpcode() != AArch64::FMOVD0 &&
      (MI.isInlineAsm() || MI.isCall() || MI.isPseudo() ||
       MI.hasUnmodeledSideEffects()))
    return 0;
  uint64_t Defined = definedZero(MI, TRI);
  if (!Known)
    return Defined;
  for (const auto *RC : {&AArch64::GPR64RegClass, &AArch64::FPR128RegClass})
    for (MCRegister Reg : *RC) {
      uint64_t Bit = registerBit(Reg, TRI);
      if ((Known & Bit) && (MI.modifiesRegister(Reg, &TRI) ||
                            MI.getDesc().hasImplicitDefOfPhysReg(Reg, &TRI)))
        Known &= ~Bit;
    }
  return Known | Defined;
}

struct KnownZero {
  uint64_t Registers = 0;
  bool Flags = false;

  bool intersect(KnownZero Other) {
    KnownZero Prev = *this;
    Registers &= Other.Registers;
    Flags &= Other.Flags;
    return Registers != Prev.Registers || Flags != Prev.Flags;
  }
};

using Propagate = function_ref<void(const MachineBasicBlock *, KnownZero)>;

void propagateBranch(const MachineInstr &MI, KnownZero State,
                     Propagate Enqueue) {
  // A direct conditional branch can skip a later terminator in its block.
  if (MI.isBranch() && !MI.isIndirectBranch() && !MI.isPseudo()) {
    bool HasTarget = false;
    for (const MachineOperand &MO : MI.explicit_operands())
      if (MO.isMBB()) {
        Enqueue(MO.getMBB(), State);
        HasTarget = true;
      }
    if (HasTarget)
      return;
  }
  for (const MachineBasicBlock *Succ : MI.getParent()->successors())
    Enqueue(Succ, State);
}

bool report(const MachineInstr &MI, const Twine &Reason) {
  const Function &F = MI.getMF()->getFunction();
  F.getContext().diagnose(DiagnosticInfoUnsupported{
      F, Twine("AArch64 zeroization verifier: ") + Reason + " in bb." +
             Twine(MI.getParent()->getNumber())});
  return false;
}

bool verifyReturn(const MachineInstr &MI, KnownZero Known, bool CheckFlags,
                  bool CheckRegisters) {
  bool Ordinary =
      MI.getOpcode() == AArch64::RET_ReallyLR || MI.getOpcode() == AArch64::RET;
  if (CheckFlags && !Ordinary)
    return report(MI, "unsupported final return protocol");
  if (CheckFlags && !Known.Flags)
    return report(MI, "NZCV is not proven zero at return");
  if (!CheckRegisters)
    return true;
  if (!Ordinary || (MI.getOpcode() == AArch64::RET &&
                    MI.getOperand(0).getReg() != AArch64::LR)) {
    if (llvm::any_of(MI.operands(), isObligation))
      return report(MI,
                    "register obligation on unsupported final return protocol");
    return true;
  }
  auto Required = requiredRegisters(MI);
  if (!Required)
    return report(MI, "missing or invalid per-exit register obligation");
  if (uint64_t Missing = *Required & ~Known.Registers) {
    unsigned Bit = llvm::countr_zero(Missing);
    return report(MI, Twine(Bit < 32 ? "X" : "Q") + Twine(Bit % 32) +
                          " is not proven zero at return");
  }
  return true;
}
} // end anonymous namespace

void llvm::recordAArch64ZeroizationObligation(MachineInstr &Exit,
                                              const BitVector &FullRegs) {
  MachineFunction &MF = *Exit.getMF();
  const auto &TRI = *MF.getSubtarget().getRegisterInfo();
  LLVMContext &Ctx = MF.getFunction().getContext();
  uint64_t Mask = 0;
  for (MCRegister Reg : FullRegs.set_bits())
    Mask |= registerBit(Reg, TRI);
  Metadata *Fields[] = {MDString::get(Ctx, ObligationTag),
                        MDString::get(Ctx, utohexstr(Mask))};
  Exit.addOperand(MF, MachineOperand::CreateMetadata(MDNode::get(Ctx, Fields)));
}

bool llvm::verifyAArch64Zeroization(const MachineFunction &MF) {
  bool CheckFlags = MF.getFunction().hasFnAttribute("zeroize-flags");
  bool CheckRegisters = shouldVerifyAArch64ZeroizedRegisters(MF);
  if (!CheckRegisters) {
    // Preserve other protocols and modes that never acquired a fixed-width
    // obligation. A later protocol change must not silently discard a record.
    for (const MachineBasicBlock &MBB : MF)
      for (const MachineInstr &MI : MBB.instrs())
        if (llvm::any_of(MI.operands(), isObligation))
          return report(
              MI, "register obligation on unsupported final function protocol");
    if (!CheckFlags)
      return true;
  }
  const auto &TRI = *MF.getSubtarget().getRegisterInfo();
  // Initially unseen blocks have no incoming paths. Once reachable, their
  // entry facts can only lose bits as predecessors (including loops) are met.
  DenseMap<const MachineBasicBlock *, KnownZero> In;
  SmallSetVector<const MachineBasicBlock *, 16> Work;
  auto Enqueue = [&](const MachineBasicBlock *MBB, KnownZero State) {
    auto [I, Inserted] = In.try_emplace(MBB, State);
    if (Inserted || I->second.intersect(State))
      Work.insert(MBB);
  };
  for (const MachineBasicBlock &MBB : MF)
    if (MBB.isEntryBlock() || MBB.isEHPad() || MBB.hasAddressTaken() ||
        MBB.isInlineAsmBrIndirectTarget())
      Enqueue(&MBB, {});

  while (!Work.empty()) {
    const MachineBasicBlock *MBB = Work.pop_back_val();
    KnownZero State = In.lookup(MBB);
    bool FallsThrough = true;
    for (const MachineInstr &MI : MBB->instrs()) {
      if (CheckRegisters && !MI.isReturn() &&
          llvm::any_of(MI.operands(), isObligation))
        return report(MI, "register obligation on a non-return instruction");
      if (MI.isReturn()) {
        if (!verifyReturn(MI, State, CheckFlags, CheckRegisters))
          return false;
        if (MI.isBarrier()) {
          FallsThrough = false;
          break;
        }
      }
      if (CheckFlags)
        State.Flags = leavesNZCVZero(MI, State.Flags, TRI);
      if (CheckRegisters)
        State.Registers = transferRegisters(MI, State.Registers, TRI);
      if (MI.isTerminator())
        propagateBranch(MI, State, Enqueue);
      if (MI.isBarrier()) {
        FallsThrough = false;
        break;
      }
    }
    if (FallsThrough) {
      const auto *Next = MBB->getNextNode();
      if (Next && MBB->isSuccessor(Next))
        Enqueue(Next, State);
      else
        for (const MachineBasicBlock *Succ : MBB->successors())
          Enqueue(Succ, State);
    }
  }
  return true;
}
