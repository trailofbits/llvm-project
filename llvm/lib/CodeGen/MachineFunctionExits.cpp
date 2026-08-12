//===- MachineFunctionExits.cpp - Classify machine function exits ---------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
//
// See llvm/CodeGen/MachineFunctionExits.h.
//
//===----------------------------------------------------------------------===//

#include "llvm/CodeGen/MachineFunctionExits.h"
#include "llvm/CodeGen/MachineBasicBlock.h"
#include "llvm/CodeGen/MachineFunction.h"
#include "llvm/CodeGen/MachineInstr.h"
#include "llvm/CodeGen/MachineOperand.h"
#include "llvm/CodeGen/TargetLowering.h"
#include "llvm/CodeGen/TargetSubtargetInfo.h"
#include "llvm/IR/GlobalValue.h"
#include "llvm/IR/RuntimeLibcalls.h"
#include "llvm/Support/raw_ostream.h"

using namespace llvm;

/// The last instruction of \p MBB that survives into the object file, or null
/// if there is none. Labels, CFI and the rest of the meta instructions are
/// skipped: they carry no control flow, so the shape of the exit is decided by
/// what is underneath them.
static const MachineInstr *getLastRealInstr(const MachineBasicBlock &MBB) {
  for (const MachineInstr &MI : reverse(MBB.instrs()))
    if (!MI.isDebugInstr() && !MI.isMetaInstruction())
      return &MI;
  return nullptr;
}

/// The name of the callee of \p MI, for a call to a known symbol, or the empty
/// string for an indirect call.
static StringRef getCalleeName(const MachineInstr &MI) {
  for (const MachineOperand &MO : MI.operands()) {
    if (MO.isGlobal())
      return MO.getGlobal()->getName();
    if (MO.isSymbol())
      return MO.getSymbolName();
  }
  return StringRef();
}

/// Whether \p MI calls the routine that resumes unwinding after a cleanup.
///
/// The name is the one the target would use to create the call, rather than a
/// hard-coded string: DwarfEHPrepare lowers a resume through these same two
/// libcalls, so asking for them back is what makes the two agree on targets
/// that do not use _Unwind_Resume.
static bool isUnwindResumeCall(const MachineInstr &MI) {
  const MachineFunction *MF = MI.getMF();
  if (!MF)
    return false;

  const TargetLowering *TLI = MF->getSubtarget().getTargetLowering();
  if (!TLI)
    return false;

  StringRef Callee = getCalleeName(MI);
  if (Callee.empty())
    return false;

  for (RTLIB::Libcall LC : {RTLIB::UNWIND_RESUME, RTLIB::CXA_END_CLEANUP})
    if (const char *Name = TLI->getLibcallName(LC))
      if (Callee == Name)
        return true;

  return false;
}

bool llvm::isEnforceableExit(MachineExitKind K) {
  switch (K) {
  case MachineExitKind::Return:
  case MachineExitKind::TailCall:
  case MachineExitKind::EHScopeReturn:
  case MachineExitKind::UnwindResume:
  case MachineExitKind::Unknown:
    return true;
  case MachineExitKind::NoReturnCall:
  case MachineExitKind::NonLocalJump:
  case MachineExitKind::Unreachable:
    return false;
  }
  llvm_unreachable("unhandled MachineExitKind");
}

StringRef llvm::getMachineExitKindName(MachineExitKind K) {
  switch (K) {
  case MachineExitKind::Return:
    return "return";
  case MachineExitKind::TailCall:
    return "tail-call";
  case MachineExitKind::EHScopeReturn:
    return "eh-scope-return";
  case MachineExitKind::UnwindResume:
    return "unwind-resume";
  case MachineExitKind::Unknown:
    return "unknown";
  case MachineExitKind::NoReturnCall:
    return "no-return-call";
  case MachineExitKind::NonLocalJump:
    return "non-local-jump";
  case MachineExitKind::Unreachable:
    return "unreachable";
  }
  llvm_unreachable("unhandled MachineExitKind");
}

std::optional<MachineExit>
llvm::classifyMachineExit(const MachineBasicBlock &MBB) {
  // A return-shaped terminator settles the kind on its own, before the
  // successor list is consulted: catchret names the block the personality
  // resumes at, so an exit out of a funclet has a successor like any branch.
  for (const MachineInstr &MI : MBB.terminators()) {
    if (!MI.isReturn())
      continue;
    if (MI.isEHScopeReturn())
      return MachineExit{&MBB, &MI, MachineExitKind::EHScopeReturn};
    // A tail call is a call marked as a return, which is how it reaches a
    // walk over return blocks despite releasing the frame first.
    if (MI.isCall())
      return MachineExit{&MBB, &MI, MachineExitKind::TailCall};
    return MachineExit{&MBB, &MI, MachineExitKind::Return};
  }

  // Everything else that leaves the function leaves it for good, so the block
  // it leaves from has nowhere else to go.
  if (!MBB.succ_empty())
    return std::nullopt;

  const MachineInstr *Last = getLastRealInstr(MBB);
  if (!Last)
    return MachineExit{&MBB, nullptr, MachineExitKind::Unreachable};

  if (Last->isCall())
    return MachineExit{&MBB, Last,
                       isUnwindResumeCall(*Last)
                           ? MachineExitKind::UnwindResume
                           : MachineExitKind::NoReturnCall};

  // A jump with no successor in this function is a jump out of it. Targets
  // spell a longjmp either as an indirect branch, once the jump buffer has
  // been reloaded, or as a barrier pseudo that expands to one later.
  if (Last->isIndirectBranch() ||
      (Last->isTerminator() && Last->isBarrier() && !Last->isBranch()))
    return MachineExit{&MBB, Last, MachineExitKind::NonLocalJump};

  // A trap is where control stops, not where it goes: the target has said so
  // by marking the instruction, and it is the one shape left here that can be
  // ruled out rather than merely not recognised.
  if (Last->getDesc().isTrap())
    return MachineExit{&MBB, Last, MachineExitKind::Unreachable};

  // Nothing else is known about this block, and not knowing has to be recorded
  // as not knowing. Falling back on Unreachable here would turn every shape
  // the classification has not learned -- inline assembly above all -- into a
  // claim that control stops in the block, which is the one answer that leaves
  // the frame and the registers alone.
  return MachineExit{&MBB, Last, MachineExitKind::Unknown};
}

void llvm::collectMachineFunctionExits(const MachineFunction &MF,
                                       SmallVectorImpl<MachineExit> &Exits) {
  for (const MachineBasicBlock &MBB : MF)
    if (std::optional<MachineExit> Exit = classifyMachineExit(MBB))
      Exits.push_back(*Exit);
}

void llvm::printMachineFunctionExits(raw_ostream &OS,
                                     const MachineFunction &MF) {
  SmallVector<MachineExit, 8> Exits;
  collectMachineFunctionExits(MF, Exits);

  OS << "exits for function '" << MF.getName() << "':\n";
  for (const MachineExit &Exit : Exits)
    OS << "  " << printMBBReference(*Exit.MBB) << ": "
       << getMachineExitKindName(Exit.Kind) << " ["
       << (isEnforceableExit(Exit.Kind) ? "in-scope" : "out-of-scope") << "]\n";
  OS << "end exits for function '" << MF.getName() << "'\n";
}
