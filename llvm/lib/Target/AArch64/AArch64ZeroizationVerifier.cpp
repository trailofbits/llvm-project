//===- AArch64ZeroizationVerifier.cpp - Final register values -------------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#include "AArch64InstrInfo.h"
#include "AArch64MachineFunctionInfo.h"
#include "AArch64Subtarget.h"
#include "AArch64Zeroization.h"
#include "Utils/AArch64BaseInfo.h"
#include "llvm/ADT/BitVector.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/STLFunctionalExtras.h"
#include "llvm/ADT/SetVector.h"
#include "llvm/ADT/StringExtras.h"
#include "llvm/CodeGen/LiveRegUnits.h"
#include "llvm/CodeGen/MachineFunction.h"
#include "llvm/CodeGen/MachineInstr.h"
#include "llvm/CodeGen/MachineRegisterInfo.h"
#include "llvm/IR/DiagnosticInfo.h"
#include "llvm/IR/Function.h"
#include "llvm/IR/LLVMContext.h"
#include "llvm/IR/Metadata.h"
#include "llvm/Support/MathExtras.h"

using namespace llvm;

namespace {
// The mask uses architectural X0-X30 and Q0-Q31 encoding numbers. It is
// independent of LLVM's internal register numbering and survives MIR replay.
// A second byte uses bit N for V(8+N)[127:64]. The saved interface describes
// the real exit operands at PEI, before it appends any retention uses. It is
// trusted compiler input when replaying final MIR.
constexpr StringLiteral ObligationTag = "aarch64.zero-call-used-regs";

uint64_t registerBit(MCRegister Reg, const TargetRegisterInfo &TRI) {
  bool Vector = AArch64::FPR128RegClass.contains(Reg);
  assert((Vector || AArch64::GPR64RegClass.contains(Reg)) &&
         "unexpected width");
  return uint64_t(1) << (TRI.getEncodingValue(Reg) + (Vector ? 32 : 0));
}

struct RegisterBits {
  uint64_t Full = 0;
  uint8_t Upper = 0;
};

// Record original interface liveness separately from the emitter's selected
// registers. Final retention uses are added later and cannot identify outputs.
struct ExitPlan {
  RegisterBits Required;
  RegisterBits Interface;
};

uint64_t fullMask(const TargetRegisterInfo &TRI,
                  function_ref<bool(MCRegister)> Matches) {
  uint64_t Bits = 0;
  for (const auto *RC : {&AArch64::GPR64RegClass, &AArch64::FPR128RegClass})
    for (MCRegister Reg : *RC)
      if (Matches(Reg))
        Bits |= registerBit(Reg, TRI);
  return Bits;
}

uint8_t upperMask(const TargetRegisterInfo &TRI,
                  function_ref<bool(MCRegister, MCRegister)> Matches) {
  uint8_t Bits = 0;
  for (unsigned Q = AArch64::Q8; Q <= AArch64::Q15; ++Q)
    if (Matches(Q, TRI.getSubReg(Q, AArch64::dsub_hi)))
      Bits |= 1u << (Q - AArch64::Q8);
  return Bits;
}

// Independent lower bound for complete registers, and exact set for the
// projected upper halves. PEI may also validly widen an allocatable smaller
// register, for example W29 when FP itself is fixed.
RegisterBits eligibleRegisters(const MachineFunction &MF) {
  const auto &STI = MF.getSubtarget<AArch64Subtarget>();
  const auto &TRI = *STI.getRegisterInfo();
  BitVector Selectable = TRI.getAllocatableSet(MF);
  LiveRegUnits Preserved(TRI);
  Preserved.addReg(TRI.getRARegister());
  uint8_t SavedLow = 0;
  for (const MCPhysReg *CS = MF.getRegInfo().getCalleeSavedRegs(); *CS; ++CS) {
    Preserved.addReg(*CS);
    if (*CS >= AArch64::D8 && *CS <= AArch64::D15)
      SavedLow |= 1u << (*CS - AArch64::D8);
  }
  RegisterBits Bits;
  Bits.Full = fullMask(TRI, [&](MCRegister R) {
    return R != AArch64::XZR && Selectable.test(R) &&
           !TRI.isFixedRegister(MF, R) && Preserved.available(R) &&
           (STI.hasFPARMv8() || AArch64::GPR64RegClass.contains(R));
  });
  if (hasAArch64ZeroizeUpperLaneABI(MF))
    Bits.Upper = upperMask(TRI, [&](MCRegister Q, MCRegister High) {
      return (SavedLow & (1u << (Q - AArch64::Q8))) && Selectable.test(Q) &&
             !TRI.isFixedRegister(MF, High) && Preserved.available(High);
    });
  return Bits;
}

template <typename T> bool readMask(const MDNode &MD, unsigned Index, T &Out) {
  auto *Str = dyn_cast_or_null<MDString>(MD.getOperand(Index));
  return Str && !Str->getString().getAsInteger(16, Out);
}

std::optional<ExitPlan> requiredRegisters(const MachineInstr &MI, bool Resume) {
  std::optional<ExitPlan> Plan;
  for (const MachineOperand &MO : MI.operands()) {
    if (!isAArch64ZeroizationObligation(MO))
      continue;
    const MDNode &MD = *MO.getMetadata();
    ExitPlan P;
    if (Plan || MD.getNumOperands() != 6 || !readMask(MD, 1, P.Required.Full) ||
        !readMask(MD, 2, P.Required.Upper) ||
        !readMask(MD, 3, P.Interface.Full) ||
        !readMask(MD, 4, P.Interface.Upper))
      return std::nullopt;
    auto *Kind = dyn_cast_or_null<MDString>(MD.getOperand(5));
    if (!Kind || Kind->getString() != (Resume ? "resume" : "return"))
      return std::nullopt;
    Plan = P;
  }
  return Plan;
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

// INS and the scalar-FP high-lane move each preserve the low 64 bits. The
// NEON form has an explicitly tied destination, while FMOV encodes the high
// lane in the opcode (the last immediate is its printed lane index).
uint8_t definedUpperZero(const MachineInstr &MI, uint64_t FullZero) {
  uint8_t Upper = FullZero >> 40;
  unsigned Opc = MI.getOpcode();
  if (Opc == AArch64::FMOVXDr || Opc == AArch64::LDRDui) {
    unsigned Encoding = MI.getOperand(0).getReg() - AArch64::D0;
    if (Encoding >= 8 && Encoding <= 15)
      Upper |= 1u << (Encoding - 8);
    return Upper;
  }
  if (Opc != AArch64::INSvi64gpr && Opc != AArch64::FMOVXDHighr)
    return Upper;
  MCRegister Q = MI.getOperand(0).getReg();
  if (Q < AArch64::Q8 || Q > AArch64::Q15)
    return Upper;
  bool Neon = Opc == AArch64::INSvi64gpr;
  if (MI.getOperand(2).getImm() == 1 &&
      MI.getOperand(Neon ? 3 : 1).getReg() == AArch64::XZR &&
      (!Neon || MI.getOperand(1).getReg() == Q))
    Upper |= 1u << (Q - AArch64::Q8);
  return Upper;
}

RegisterBits transferRegisters(const MachineInstr &MI, RegisterBits Known,
                               const TargetRegisterInfo &TRI) {
  if (MI.isMetaInstruction())
    return Known;
  if (!isNZCVWrite(MI) && MI.getOpcode() != AArch64::FMOVD0 &&
      (MI.isInlineAsm() || MI.isCall() || MI.isPseudo() ||
       MI.hasUnmodeledSideEffects()))
    return {};
  uint64_t Full = definedZero(MI, TRI);
  uint8_t UpperZero = definedUpperZero(MI, Full);
  if (!Known.Full && !Known.Upper)
    return {Full, UpperZero};
  for (const auto *RC : {&AArch64::GPR64RegClass, &AArch64::FPR128RegClass})
    for (MCRegister Reg : *RC) {
      uint64_t Bit = registerBit(Reg, TRI);
      uint8_t Upper = Reg >= AArch64::Q8 && Reg <= AArch64::Q15
                          ? 1u << (Reg - AArch64::Q8)
                          : 0;
      // Even an unrecognized D definition can change the upper half of Q.
      if (((Known.Full & Bit) || (Known.Upper & Upper)) &&
          (MI.modifiesRegister(Reg, &TRI) ||
           MI.getDesc().hasImplicitDefOfPhysReg(Reg, &TRI))) {
        Known.Full &= ~Bit;
        Known.Upper &= ~Upper;
      }
    }
  Known.Full |= Full;
  Known.Upper |= UpperZero;
  return Known;
}

struct KnownZero {
  RegisterBits Registers;
  bool Flags = false;

  bool intersect(KnownZero Other) {
    KnownZero Prev = *this;
    Registers.Full &= Other.Registers.Full;
    Registers.Upper &= Other.Registers.Upper;
    Flags &= Other.Flags;
    return Registers.Full != Prev.Registers.Full ||
           Registers.Upper != Prev.Registers.Upper || Flags != Prev.Flags;
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

struct Checks {
  bool Flags;
  bool Registers;
  RegisterBits Eligible;
};

bool verifyExit(const MachineInstr &MI, KnownZero Known, const Checks &Check,
                bool Resume) {
  const MachineFunction &MF = *MI.getMF();
  bool Ordinary =
      MF.getSubtarget().getFrameLowering()->isOrdinaryZeroizeReturn(MI);
  const auto &AFI = *MF.getInfo<AArch64FunctionInfo>();
  if (!Resume && MF.getFunction().hasZeroizeStack() &&
      AFI.shouldSignReturnAddress(MF)) {
    unsigned Expected =
        AFI.shouldSignWithBKey() ? AArch64::RETAB : AArch64::RETAA;
    if (MI.getOpcode() != Expected)
      return report(MI, "missing matching authenticated return");
    Ordinary = true;
  }
  if (Check.Flags && !Ordinary && !Resume)
    return report(MI, "unsupported final return protocol");
  StringRef Site = Resume ? "outgoing _Unwind_Resume" : "return";
  if (Check.Flags && !Known.Flags)
    return report(MI, Twine("NZCV is not proven zero at ") + Site);
  if (!Check.Registers)
    return true;
  if (!Resume && !Ordinary) {
    if (llvm::any_of(MI.operands(), isAArch64ZeroizationObligation))
      return report(MI,
                    "register obligation on unsupported final return protocol");
    return true;
  }
  auto P = requiredRegisters(MI, Resume);
  if (!P)
    return report(MI, "missing or invalid per-exit register obligation");
  if ((Resume && !(P->Interface.Full & 1)) ||
      (Check.Eligible.Full & ~P->Interface.Full & ~P->Required.Full) ||
      (P->Required.Full & P->Interface.Full) ||
      P->Required.Upper != (Check.Eligible.Upper & ~P->Interface.Upper))
    return report(
        MI,
        "register obligation disagrees with eligible units and exit interface");
  if (uint64_t Missing = P->Required.Full & ~Known.Registers.Full) {
    unsigned Bit = llvm::countr_zero(Missing);
    return report(MI, Twine(Bit < 32 ? "X" : "Q") + Twine(Bit % 32) +
                          " is not proven zero at " + Site);
  }
  if (uint8_t Missing = P->Required.Upper & ~Known.Registers.Upper)
    return report(MI, Twine("V") + Twine(8 + llvm::countr_zero(Missing)) +
                          "[127:64] is not proven zero at " + Site);
  return true;
}
} // end anonymous namespace

bool llvm::isAArch64ZeroizationObligation(const MachineOperand &MO) {
  if (!MO.isMetadata() || !MO.getMetadata()->getNumOperands())
    return false;
  auto *Tag = dyn_cast_or_null<MDString>(MO.getMetadata()->getOperand(0));
  return Tag && Tag->getString() == ObligationTag;
}

void llvm::recordAArch64ZeroizationObligation(MachineInstr &Exit,
                                              const BitVector &FullRegs,
                                              const BitVector &Selected,
                                              const LiveRegUnits &Interface) {
  MachineFunction &MF = *Exit.getMF();
  const auto &TRI = *MF.getSubtarget().getRegisterInfo();
  LLVMContext &Ctx = MF.getFunction().getContext();
  uint64_t Full = 0;
  for (MCRegister Reg : FullRegs.set_bits())
    Full |= registerBit(Reg, TRI);
  RegisterBits Original;
  Original.Full =
      fullMask(TRI, [&](MCRegister R) { return !Interface.available(R); });
  Original.Upper = upperMask(TRI, [&](MCRegister, MCRegister High) {
    return !Interface.available(High);
  });
  uint8_t RequiredUpper = upperMask(
      TRI, [&](MCRegister, MCRegister High) { return Selected.test(High); });
  Metadata *Fields[] = {
      MDString::get(Ctx, ObligationTag),
      MDString::get(Ctx, utohexstr(Full)),
      MDString::get(Ctx, utohexstr(RequiredUpper)),
      MDString::get(Ctx, utohexstr(Original.Full)),
      MDString::get(Ctx, utohexstr(Original.Upper)),
      MDString::get(Ctx, Exit.isCall() ? "resume" : "return")};
  Exit.addOperand(MF, MachineOperand::CreateMetadata(MDNode::get(Ctx, Fields)));
}

bool llvm::verifyAArch64Zeroization(const MachineFunction &MF) {
  bool CheckFlags = MF.getFunction().hasFnAttribute("zeroize-flags");
  bool CheckRegisters = shouldVerifyAArch64ZeroizedRegisters(MF);
  Checks Check{CheckFlags, CheckRegisters,
               CheckRegisters ? eligibleRegisters(MF) : RegisterBits{}};
  if (!CheckRegisters) {
    // Preserve other protocols and modes that never acquired a fixed-width
    // obligation. A later protocol change must not silently discard a record.
    for (const MachineBasicBlock &MBB : MF)
      for (const MachineInstr &MI : MBB.instrs())
        if (llvm::any_of(MI.operands(), isAArch64ZeroizationObligation))
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
      bool Resume = isAArch64ZeroizeShadowResume(MI);
      if (!Resume && (CheckFlags || MF.getFunction().hasZeroizeStack()) &&
          isAArch64ZeroizeUnwindResume(MI))
        return report(MI, "unsupported final unwind protocol");
      if (CheckRegisters && !MI.isReturn() && !Resume &&
          llvm::any_of(MI.operands(), isAArch64ZeroizationObligation))
        return report(MI, "register obligation on a non-return instruction");
      if (MI.isReturn() || Resume) {
        if (!verifyExit(MI, State, Check, Resume))
          return false;
        if (MI.isBarrier() || Resume) {
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
