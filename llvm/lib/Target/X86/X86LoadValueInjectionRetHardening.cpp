//===-- X86LoadValueInjectionRetHardening.cpp - LVI RET hardening for x86 --==//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
///
/// Description: Replaces every `ret` instruction with the sequence:
/// ```
/// pop <scratch-reg>
/// lfence
/// jmp *<scratch-reg>
/// ```
/// where `<scratch-reg>` is some available scratch register, according to the
/// calling convention of the function being mitigated.
///
//===----------------------------------------------------------------------===//

#include "X86.h"
#include "X86InstrBuilder.h"
#include "X86Subtarget.h"
#include "X86ZeroizeLVIReturn.h"
#include "llvm/ADT/Statistic.h"
#include "llvm/CodeGen/CFIInstBuilder.h"
#include "llvm/CodeGen/MachineBasicBlock.h"
#include "llvm/CodeGen/MachineFunction.h"
#include "llvm/CodeGen/MachineFunctionPass.h"
#include "llvm/CodeGen/MachineInstrBuilder.h"
#include "llvm/IR/DiagnosticInfo.h"
#include "llvm/IR/Function.h"
#include "llvm/Support/Debug.h"

using namespace llvm;

#define PASS_KEY "x86-lvi-ret"
#define DEBUG_TYPE PASS_KEY

STATISTIC(NumFences, "Number of LFENCEs inserted for LVI mitigation");
STATISTIC(NumFunctionsConsidered, "Number of functions analyzed");
STATISTIC(NumFunctionsMitigated, "Number of functions for which mitigations "
                                 "were deployed");

namespace {

constexpr StringRef X86LVIRetPassName =
    "X86 Load Value Injection (LVI) Ret-Hardening";

class X86LoadValueInjectionRetHardeningLegacy : public MachineFunctionPass {
public:
  X86LoadValueInjectionRetHardeningLegacy() : MachineFunctionPass(ID) {}
  StringRef getPassName() const override { return X86LVIRetPassName; }
  bool runOnMachineFunction(MachineFunction &MF) override;

  static char ID;
};

} // end anonymous namespace

char X86LoadValueInjectionRetHardeningLegacy::ID = 0;

bool llvm::isX86ZeroizeLVIReturn(const MachineFunction &MF) {
  const Function &F = MF.getFunction();
  const X86Subtarget &ST = MF.getSubtarget<X86Subtarget>();
  return ST.useLVIControlFlowIntegrity() && ST.is64Bit() &&
         !ST.isTarget64BitILP32() && ST.getTargetTriple().isOSBinFormatELF() &&
         F.getCallingConv() == CallingConv::C && !F.hasPersonalityFn() &&
         !F.isVarArg() && !F.hasFnAttribute("no_caller_saved_registers") &&
         F.hasFnAttribute("zeroize-flags") &&
         F.hasFnAttribute("zeroize-stack") &&
         F.getFnAttribute("zeroize-stack").getValueAsString() == "used" &&
         F.hasFnAttribute("zero-call-used-regs") &&
         F.getFnAttribute("zero-call-used-regs").getValueAsString() == "all";
}

static bool isSysVScratch(MCRegister Reg) {
  return llvm::is_contained({X86::RAX, X86::RCX, X86::RDX, X86::RSI, X86::RDI,
                             X86::R8, X86::R9, X86::R10, X86::R11},
                            Reg.id());
}

static bool hasPublicReturnTransfer(const MachineBasicBlock &MBB,
                                    const X86RegisterInfo &TRI) {
  auto Insns =
      llvm::make_filter_range(llvm::reverse(MBB), [](const MachineInstr &MI) {
        return !MI.isDebugInstr() && !MI.isCFIInstruction();
      });
  auto It = Insns.begin();
  auto Take = [&](unsigned Opcode) -> const MachineInstr * {
    if (It == Insns.end() || It->getOpcode() != Opcode)
      return nullptr;
    return &*It++;
  };
  const MachineInstr *Jump = Take(X86::JMP64r);
  if (!Jump || !Take(X86::LFENCE))
    return false;
  const MachineInstr *Pop = Take(X86::POP64r);
  const MachineInstr *Retention = Take(TargetOpcode::FAKE_USE);
  if (!Pop || !Retention)
    return false;
  MCRegister Scratch = Pop->getOperand(0).getReg();
  if (!isSysVScratch(Scratch) || Jump->getOperand(0).getReg() != Scratch)
    return false;
  // Genuine return operands are carried through the jump. They cannot overlap
  // the register receiving the caller's return address.
  for (const MachineOperand &MO : Jump->implicit_operands())
    if (MO.isReg() && MO.isUse() && TRI.regsOverlap(Scratch, MO.getReg()))
      return false;
  // PEI retains a 32-bit XOR (which clears the full 64-bit register) or a
  // full-width write at this boundary. Nothing may write between it and POP.
  MCRegister Low = TRI.getSubReg(Scratch, X86::sub_32bit);
  if (!Retention->readsRegister(Low, nullptr) &&
      !Retention->readsRegister(Scratch, nullptr))
    return false;
  for (; It != Insns.end(); ++It) {
    if (!It->modifiesRegister(Scratch, &TRI))
      continue;
    // A retained use is not a proof of a complete clear. Match the last
    // physical definition, including any overlapping subregister write.
    return It->getOpcode() == X86::XOR32rr &&
           It->getOperand(0).getReg() == Low &&
           It->getOperand(1).getReg() == Low &&
           It->getOperand(2).getReg() == Low;
  }
  return false;
}

bool llvm::verifyX86ZeroizeLVIReturns(const MachineFunction &MF) {
  const auto &TRI = *MF.getSubtarget<X86Subtarget>().getRegisterInfo();
  for (const MachineBasicBlock &MBB : MF) {
    if (MBB.succ_empty() && !hasPublicReturnTransfer(MBB, TRI)) {
      MF.getFunction().getContext().diagnose(DiagnosticInfoUnsupported{
          MF.getFunction(),
          "cannot verify the protected X86 LVI return transfer"});
      return false;
    }
  }
  return true;
}

static bool runX86LoadValueInjectionRetHardening(MachineFunction &MF) {
  const X86Subtarget *Subtarget = &MF.getSubtarget<X86Subtarget>();
  if (!Subtarget->useLVIControlFlowIntegrity() || !Subtarget->is64Bit())
    return false; // FIXME: support 32-bit

  LLVM_DEBUG(dbgs() << "***** " << X86LVIRetPassName << " : " << MF.getName()
                    << " *****\n");
  ++NumFunctionsConsidered;
  const X86RegisterInfo *TRI = Subtarget->getRegisterInfo();
  const X86InstrInfo *TII = Subtarget->getInstrInfo();

  bool Modified = false;
  for (auto &MBB : MF) {
    for (auto MBBI = MBB.begin(); MBBI != MBB.end(); ++MBBI) {
      if (MBBI->getOpcode() != X86::RET64)
        continue;

      unsigned ClobberReg = TRI->findDeadCallerSavedReg(MBB, MBBI);
      const bool Protected = isX86ZeroizeLVIReturn(MF);
      if (Protected && !isSysVScratch(ClobberReg)) {
        MF.getFunction().getContext().diagnose(DiagnosticInfoUnsupported{
            MF.getFunction(),
            "protected X86 LVI return needs a free SysV scratch register"});
        continue;
      }
      if (ClobberReg != X86::NoRegister) {
        BuildMI(MBB, MBBI, DebugLoc(), TII->get(X86::POP64r))
            .addReg(ClobberReg, RegState::Define)
            .setMIFlag(MachineInstr::FrameDestroy);
        bool EmitCFI = Protected && MF.needsFrameMoves();
        MachineBasicBlock *Next = MBB.getNextNode();
        const bool HasFollowingRows = EmitCFI && Next && !MBB.isEndSection();
        CFIInstBuilder CFI(MBB, MBBI, MachineInstr::FrameDestroy);
        if (EmitCFI) {
          if (HasFollowingRows)
            CFI.insertCFIInst(MCCFIInstruction::createRememberState(nullptr));
          CFI.buildDefCFA(X86::RSP, 0);
          CFI.buildRegister(X86::RIP, ClobberReg);
        }
        BuildMI(MBB, MBBI, DebugLoc(), TII->get(X86::LFENCE));
        auto Jump = BuildMI(MBB, MBBI, DebugLoc(), TII->get(X86::JMP64r))
                        .addReg(ClobberReg);
        if (Protected) {
          for (const MachineOperand &MO : MBBI->implicit_operands())
            if (MO.isReg() && MO.isUse())
              Jump.add(MO);
        }
        if (HasFollowingRows) {
          CFIInstBuilder AtNext(*Next, Next->begin(),
                                MachineInstr::FrameDestroy);
          AtNext.insertCFIInst(MCCFIInstruction::createRestoreState(nullptr));
        }
        MBB.erase(MBBI);
      } else {
        // In case there is no available scratch register, we can still read
        // from RSP to assert that RSP points to a valid page. The write to RSP
        // is also helpful because it verifies that the stack's write
        // permissions are intact.
        MachineInstr *Fence =
            BuildMI(MBB, MBBI, DebugLoc(), TII->get(X86::LFENCE));
        addRegOffset(BuildMI(MBB, Fence, DebugLoc(), TII->get(X86::SHL64mi)),
                     X86::RSP, false, 0)
            .addImm(0)
            ->addRegisterDead(X86::EFLAGS, TRI);
      }

      ++NumFences;
      Modified = true;
      break;
    }
  }

  if (Modified)
    ++NumFunctionsMitigated;
  return Modified;
}

bool X86LoadValueInjectionRetHardeningLegacy::runOnMachineFunction(
    MachineFunction &MF) {
  // Don't skip functions with the "optnone" attr but participate in opt-bisect.
  // Note: NewPM implements this behavior by default.
  const Function &F = MF.getFunction();
  if (!F.hasOptNone() && skipFunction(F))
    return false;

  return runX86LoadValueInjectionRetHardening(MF);
}

PreservedAnalyses X86LoadValueInjectionRetHardeningPass::run(
    MachineFunction &MF, MachineFunctionAnalysisManager &MFAM) {
  return runX86LoadValueInjectionRetHardening(MF)
             ? getMachineFunctionPassPreservedAnalyses()
                   .preserveSet<CFGAnalyses>()
             : PreservedAnalyses::all();
}

INITIALIZE_PASS(X86LoadValueInjectionRetHardeningLegacy, PASS_KEY,
                "X86 LVI ret hardener", false, false)

FunctionPass *llvm::createX86LoadValueInjectionRetHardeningLegacyPass() {
  return new X86LoadValueInjectionRetHardeningLegacy();
}
