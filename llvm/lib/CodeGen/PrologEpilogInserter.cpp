//===- PrologEpilogInserter.cpp - Insert Prolog/Epilog code in function ---===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
//
// This pass is responsible for finalizing the functions frame layout, saving
// callee saved registers, and for emitting prolog & epilog code for the
// function.
//
// This pass must be run after register allocation.  After this pass is
// executed, it is illegal to construct MO_FrameIndex operands.
//
//===----------------------------------------------------------------------===//

#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/BitVector.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SetVector.h"
#include "llvm/ADT/SmallPtrSet.h"
#include "llvm/ADT/SmallSet.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/Statistic.h"
#include "llvm/Analysis/OptimizationRemarkEmitter.h"
#include "llvm/CodeGen/MachineBasicBlock.h"
#include "llvm/CodeGen/MachineDominators.h"
#include "llvm/CodeGen/MachineFrameInfo.h"
#include "llvm/CodeGen/MachineFunction.h"
#include "llvm/CodeGen/MachineFunctionPass.h"
#include "llvm/CodeGen/MachineInstr.h"
#include "llvm/CodeGen/MachineLoopInfo.h"
#include "llvm/CodeGen/MachineModuleInfo.h"
#include "llvm/CodeGen/MachineOperand.h"
#include "llvm/CodeGen/MachineOptimizationRemarkEmitter.h"
#include "llvm/CodeGen/MachineRegisterInfo.h"
#include "llvm/CodeGen/PEI.h"
#include "llvm/CodeGen/RegisterClassInfo.h"
#include "llvm/CodeGen/RegisterScavenging.h"
#include "llvm/CodeGen/TargetFrameLowering.h"
#include "llvm/CodeGen/TargetInstrInfo.h"
#include "llvm/CodeGen/TargetLowering.h"
#include "llvm/CodeGen/TargetOpcodes.h"
#include "llvm/CodeGen/TargetRegisterInfo.h"
#include "llvm/CodeGen/TargetSubtargetInfo.h"
#include "llvm/CodeGen/WinEHFuncInfo.h"
#include "llvm/IR/Attributes.h"
#include "llvm/IR/CallingConv.h"
#include "llvm/IR/DebugInfoMetadata.h"
#include "llvm/IR/DiagnosticInfo.h"
#include "llvm/IR/Function.h"
#include "llvm/IR/GlobalValue.h"
#include "llvm/IR/LLVMContext.h"
#include "llvm/IR/RuntimeLibcalls.h"
#include "llvm/InitializePasses.h"
#include "llvm/Pass.h"
#include "llvm/Support/CodeGen.h"
#include "llvm/Support/CommandLine.h"
#include "llvm/Support/Debug.h"
#include "llvm/Support/ErrorHandling.h"
#include "llvm/Support/FormatVariadic.h"
#include "llvm/Support/raw_ostream.h"
#include "llvm/Target/TargetMachine.h"
#include "llvm/Target/TargetOptions.h"
#include <algorithm>
#include <cassert>
#include <cstdint>
#include <limits>
#include <utility>
#include <vector>

using namespace llvm;

#define DEBUG_TYPE "prolog-epilog"

using MBBVector = SmallVector<MachineBasicBlock *, 4>;

STATISTIC(NumLeafFuncWithSpills, "Number of leaf functions with CSRs");
STATISTIC(NumFuncSeen, "Number of functions seen in PEI");

// Prints the clearing sequence at each in-scope exit. Not gated on assertions
// or statistics: the order is the property being enforced, so it has to be
// checkable in the configuration a release compiler ships in.
static cl::opt<bool> PrintClearingSequence(
    "pei-print-clearing-sequence", cl::Hidden,
    cl::desc("Print the clearing sequence emitted at each in-scope exit, in "
             "the order its steps run"));

// A stand-in for a step that is not written yet. Clearing the stack frame is
// trailofbits/vspells-ct-internal-notes#26 and no target implements it, so the
// step that would declare the registers it worked through declares nothing,
// and the coverage the register clear gives those registers has no producer to
// exercise it. This option supplies one: it stands in for a target that clears
// the frame using the named registers. It makes the stack-clearing step
// declare them and emit nothing else, which is the part of a real
// implementation this file has to cope with. Hidden, and inert unless a test
// asks for it.
static cl::list<std::string> StandInStackScratchRegs(
    "pei-stack-clear-scratch-regs", cl::Hidden, cl::CommaSeparated,
    cl::desc("Registers the stack-clearing step is to declare as the scratch "
             "it used, standing in for the implementation of that step"));

namespace {

//===----------------------------------------------------------------------===//
// The clearing sequence.
//
// A function told to destroy what it leaves behind has several things to clear,
// and they are not independent: clearing the frame needs registers, and every
// step writes the flags. So an exit emits one ordered sequence, run at every
// in-scope exit, not a set of independent steps; the order is enforced.
//
// The order is ClearStack, then ClearRegisters, then ClearFlags. Each position
// has a reason that outlives whichever implementation sits behind it:
//
//  - ClearStack is first because it needs registers: the value and the address
//    it stores through are live in registers derived from the frame, so it
//    leaves in registers what it took out of memory, and a register clear in
//    front of it would be undone. No target implements it yet; whoever does
//    must name those registers so the following register clear covers them.
//
//  - ClearRegisters is after every step that needs a register and before every
//    step that does not, so it sees the registers' final state. Anything added
//    later that computes an address, length or value must go in front of it.
//
//  - ClearFlags is last because every other step writes the flags (an x86
//    register clear xors; a looping stack clear sets them from the count), so a
//    flag clear placed earlier would be overwritten.
//
// The order is over the emitted code, not over one insertion point. Today every
// step emits at the exit's insertion point, after the epilogue. A step that has
// to run earlier (a frame clear, before the epilogue moves SP and the frame
// stops being addressable) still has to leave every later step behind it in
// program order.
//
// Two whole-sequence invariants a later step must keep:
//
//  - It runs only at the exits getEnforceableExit() picks, decided once rather
//    than per step. A step that cannot be placed at an in-scope exit is a gap to
//    record, not a licence to pick its own sites.
//
//  - It does not depend on secret values: which steps run comes from attributes
//    and target capabilities, where they run from control-flow shape. Two runs
//    of a protected function execute the same sequence.
//
//===----------------------------------------------------------------------===//

/// One step of the clearing sequence. The order is not this enumeration's
/// order but ClearingSequence's; see the comment above.
enum class ClearingStep {
  /// Clear the stack frame, for "zeroize-stack". No target implements this
  /// yet.
  ClearStack,

  /// Clear the call-used registers, for "zero-call-used-regs".
  ClearRegisters,

  /// Clear the condition flags. Nothing implements this yet and nothing can
  /// ask for it: the flag register classes are not allocatable, so the
  /// register clear cannot reach them and a mechanism of its own is needed.
  ClearFlags,
};

/// The steps of the clearing sequence, in the order they run at every in-scope
/// exit. This array is the order: it is what the emission walks and what the
/// tests pin.
constexpr ClearingStep ClearingSequence[] = {
    ClearingStep::ClearStack,
    ClearingStep::ClearRegisters,
    ClearingStep::ClearFlags,
};

/// What a step of the sequence does in a given function.
enum class ClearingDisposition {
  /// The function did not ask for this step.
  NotRequested,

  /// The function asked for it and the target cannot do it. The request has
  /// been reported; nothing is emitted.
  Unsupported,

  /// Nothing in the tree emits this step yet. The step holds its place in the
  /// order so that the implementation lands in the right one.
  Unimplemented,

  /// The step emits at every in-scope exit.
  Emit,
};

/// What each step of the sequence does in one function, decided once and before
/// any of it is emitted, because the sequence must be the same at every exit.
///
/// Which steps run is the function's to decide. What a step covers is not: a
/// clear can only cover registers dead where it runs, and that differs per
/// exit. So the plan holds just the mode's function-wide choice of registers;
/// the rest is settled per exit. See computeRegsToClearAtExit.
struct ExitClearingPlan {
  ClearingDisposition Stack = ClearingDisposition::NotRequested;
  ClearingDisposition Registers = ClearingDisposition::NotRequested;
  ClearingDisposition Flags = ClearingDisposition::NotRequested;

  /// The registers ClearRegisters may clear anywhere in the function: what the
  /// mode selects, less what the function must preserve at every exit. Not the
  /// set cleared at any one exit, which is this less what that exit needs.
  BitVector CandidateRegsToZero;

  ClearingDisposition dispositionOf(ClearingStep Step) const {
    switch (Step) {
    case ClearingStep::ClearStack:
      return Stack;
    case ClearingStep::ClearRegisters:
      return Registers;
    case ClearingStep::ClearFlags:
      return Flags;
    }
    llvm_unreachable("unhandled ClearingStep");
  }

  bool anyStepEmits() const {
    return any_of(ClearingSequence, [this](ClearingStep Step) {
      return dispositionOf(Step) == ClearingDisposition::Emit;
    });
  }
};

/// The name of \p Step, as printed by -pei-print-clearing-sequence.
StringRef getClearingStepName(ClearingStep Step) {
  switch (Step) {
  case ClearingStep::ClearStack:
    return "clear-stack";
  case ClearingStep::ClearRegisters:
    return "clear-registers";
  case ClearingStep::ClearFlags:
    return "clear-flags";
  }
  llvm_unreachable("unhandled ClearingStep");
}

/// The name of \p D, as printed by -pei-print-clearing-sequence.
StringRef getClearingDispositionName(ClearingDisposition D) {
  switch (D) {
  case ClearingDisposition::NotRequested:
    return "not-requested";
  case ClearingDisposition::Unsupported:
    return "unsupported";
  case ClearingDisposition::Unimplemented:
    return "unimplemented";
  case ClearingDisposition::Emit:
    return "emitted";
  }
  llvm_unreachable("unhandled ClearingDisposition");
}

class PEIImpl {
  RegScavenger *RS = nullptr;

  // Save and Restore blocks of the current function. Typically there is a
  // single save block, unless Windows EH funclets are involved.
  MBBVector SaveBlocks;
  MBBVector RestoreBlocks;

  // Flag to control whether to use the register scavenger to resolve
  // frame index materialization registers. Set according to
  // TRI->requiresFrameIndexScavenging() for the current function.
  bool FrameIndexVirtualScavenging = false;

  // Flag to control whether the scavenger should be passed even though
  // FrameIndexVirtualScavenging is used.
  bool FrameIndexEliminationScavenging = false;

  // Emit remarks.
  MachineOptimizationRemarkEmitter *ORE = nullptr;

  void calculateCallFrameInfo(MachineFunction &MF);
  void calculateSaveRestoreBlocks(MachineFunction &MF);
  void spillCalleeSavedRegs(MachineFunction &MF);

  void calculateFrameObjectOffsets(MachineFunction &MF);
  void replaceFrameIndices(MachineFunction &MF);
  void replaceFrameIndices(MachineBasicBlock *BB, MachineFunction &MF,
                           int &SPAdj);
  // Frame indices in debug values are encoded in a target independent
  // way with simply the frame index and offset rather than any
  // target-specific addressing mode.
  bool replaceFrameIndexDebugInstr(MachineFunction &MF, MachineInstr &MI,
                                   unsigned OpIdx, int SPAdj = 0);
  // Does same as replaceFrameIndices but using the backward MIR walk and
  // backward register scavenger walk.
  void replaceFrameIndicesBackward(MachineFunction &MF);
  void replaceFrameIndicesBackward(MachineBasicBlock *BB, MachineFunction &MF,
                                   int &SPAdj);

  void insertPrologEpilogCode(MachineFunction &MF);
  void insertClearingSequences(MachineFunction &MF);
  void planClearingSequence(MachineFunction &MF, ExitClearingPlan &Plan);
  ClearingDisposition planClearStack(MachineFunction &MF);
  ClearingDisposition planClearRegisters(MachineFunction &MF,
                                         BitVector &CandidateRegsToZero);
  ClearingDisposition planClearRegistersForScratch(
      MachineFunction &MF, BitVector &CandidateRegsToZero);
  void emitClearingStep(ClearingStep Step, const ExitClearingPlan &Plan,
                        MachineBasicBlock &MBB,
                        MachineBasicBlock::iterator InsertPt,
                        BitVector &ScratchRegs, BitVector &ClearedRegs);
  void diagnoseIgnoredZeroizeRequestsOnNakedFunction(MachineFunction &MF);

public:
  PEIImpl(MachineOptimizationRemarkEmitter *ORE) : ORE(ORE) {}
  bool run(MachineFunction &MF);
};

class PEILegacy : public MachineFunctionPass {
public:
  static char ID;

  PEILegacy() : MachineFunctionPass(ID) {}

  void getAnalysisUsage(AnalysisUsage &AU) const override;

  /// runOnMachineFunction - Insert prolog/epilog code and replace abstract
  /// frame indexes with appropriate references.
  bool runOnMachineFunction(MachineFunction &MF) override;
};

} // end anonymous namespace

char PEILegacy::ID = 0;

char &llvm::PrologEpilogCodeInserterID = PEILegacy::ID;

INITIALIZE_PASS_BEGIN(PEILegacy, DEBUG_TYPE, "Prologue/Epilogue Insertion",
                      false, false)
INITIALIZE_PASS_DEPENDENCY(MachineLoopInfoWrapperPass)
INITIALIZE_PASS_DEPENDENCY(MachineDominatorTreeWrapperPass)
INITIALIZE_PASS_DEPENDENCY(MachineOptimizationRemarkEmitterPass)
INITIALIZE_PASS_END(PEILegacy, DEBUG_TYPE,
                    "Prologue/Epilogue Insertion & Frame Finalization", false,
                    false)

MachineFunctionPass *llvm::createPrologEpilogInserterPass() {
  return new PEILegacy();
}

STATISTIC(NumBytesStackSpace,
          "Number of bytes used for stack in all functions");

void PEILegacy::getAnalysisUsage(AnalysisUsage &AU) const {
  AU.setPreservesCFG();
  AU.addRequired<MachineOptimizationRemarkEmitterPass>();
  MachineFunctionPass::getAnalysisUsage(AU);
}

/// StackObjSet - A set of stack object indexes
using StackObjSet = SmallSetVector<int, 8>;

using SavedDbgValuesMap =
    SmallDenseMap<MachineBasicBlock *, SmallVector<MachineInstr *, 4>, 4>;

/// Stash DBG_VALUEs that describe parameters and which are placed at the start
/// of the block. Later on, after the prologue code has been emitted, the
/// stashed DBG_VALUEs will be reinserted at the start of the block.
static void stashEntryDbgValues(MachineBasicBlock &MBB,
                                SavedDbgValuesMap &EntryDbgValues) {
  SmallVector<const MachineInstr *, 4> FrameIndexValues;

  for (auto &MI : MBB) {
    if (!MI.isDebugInstr())
      break;
    if (!MI.isDebugValue() || !MI.getDebugVariable()->isParameter())
      continue;
    if (any_of(MI.debug_operands(),
               [](const MachineOperand &MO) { return MO.isFI(); })) {
      // We can only emit valid locations for frame indices after the frame
      // setup, so do not stash away them.
      FrameIndexValues.push_back(&MI);
      continue;
    }
    const DILocalVariable *Var = MI.getDebugVariable();
    const DIExpression *Expr = MI.getDebugExpression();
    auto Overlaps = [Var, Expr](const MachineInstr *DV) {
      return Var == DV->getDebugVariable() &&
             Expr->fragmentsOverlap(DV->getDebugExpression());
    };
    // See if the debug value overlaps with any preceding debug value that will
    // not be stashed. If that is the case, then we can't stash this value, as
    // we would then reorder the values at reinsertion.
    if (llvm::none_of(FrameIndexValues, Overlaps))
      EntryDbgValues[&MBB].push_back(&MI);
  }

  // Remove stashed debug values from the block.
  if (auto It = EntryDbgValues.find(&MBB); It != EntryDbgValues.end())
    for (auto *MI : It->second)
      MI->removeFromParent();
}

bool PEIImpl::run(MachineFunction &MF) {
  NumFuncSeen++;
  const Function &F = MF.getFunction();
  const TargetRegisterInfo *TRI = MF.getSubtarget().getRegisterInfo();
  const TargetFrameLowering *TFI = MF.getSubtarget().getFrameLowering();

  RS = TRI->requiresRegisterScavenging(MF) ? new RegScavenger() : nullptr;
  FrameIndexVirtualScavenging = TRI->requiresFrameIndexScavenging(MF);

  // Spill frame pointer and/or base pointer registers if they are clobbered.
  // It is placed before call frame instruction elimination so it will not mess
  // with stack arguments.
  TFI->spillFPBP(MF);

  // Calculate the MaxCallFrameSize value for the function's frame
  // information. Also eliminates call frame pseudo instructions.
  calculateCallFrameInfo(MF);

  // Determine placement of CSR spill/restore code and prolog/epilog code:
  // place all spills in the entry block, all restores in return blocks.
  calculateSaveRestoreBlocks(MF);

  // Stash away DBG_VALUEs that should not be moved by insertion of prolog code.
  SavedDbgValuesMap EntryDbgValues;
  for (MachineBasicBlock *SaveBlock : SaveBlocks)
    stashEntryDbgValues(*SaveBlock, EntryDbgValues);

  // Handle CSR spilling and restoring, for targets that need it.
  if (MF.getTarget().usesPhysRegsForValues())
    spillCalleeSavedRegs(MF);

  // Allow the target machine to make final modifications to the function
  // before the frame layout is finalized.
  TFI->processFunctionBeforeFrameFinalized(MF, RS);

  // Calculate actual frame offsets for all abstract stack objects...
  calculateFrameObjectOffsets(MF);

  // Report a request no target could honor, before asking about target support.
  // A request the target cannot discharge is instead reported by
  // planClearStack/planClearRegisters, from within insertClearingSequences
  // below; that only runs for a function that reaches insertPrologEpilogCode,
  // which a naked function never does, so this is the one report a naked
  // function gets even though it still carries the attribute.
  diagnoseIgnoredZeroizeRequestsOnNakedFunction(MF);

  // Add prolog and epilog code to the function.  This function is required
  // to align the stack frame as necessary for any stack variables or
  // called functions.  Because of this, calculateCalleeSavedRegisters()
  // must be called before this function in order to set the AdjustsStack
  // and MaxCallFrameSize variables.
  if (!F.hasFnAttribute(Attribute::Naked))
    insertPrologEpilogCode(MF);

  // Reinsert stashed debug values at the start of the entry blocks.
  for (auto &I : EntryDbgValues)
    I.first->insert(I.first->begin(), I.second.begin(), I.second.end());

  // Allow the target machine to make final modifications to the function
  // before the frame layout is finalized.
  TFI->processFunctionBeforeFrameIndicesReplaced(MF, RS);

  // Replace all MO_FrameIndex operands with physical register references
  // and actual offsets.
  if (TFI->needsFrameIndexResolution(MF)) {
    // Allow the target to determine this after knowing the frame size.
    FrameIndexEliminationScavenging =
        (RS && !FrameIndexVirtualScavenging) ||
        TRI->requiresFrameIndexReplacementScavenging(MF);

    if (TRI->eliminateFrameIndicesBackwards())
      replaceFrameIndicesBackward(MF);
    else
      replaceFrameIndices(MF);
  }

  // If register scavenging is needed, as we've enabled doing it as a
  // post-pass, scavenge the virtual registers that frame index elimination
  // inserted.
  if (TRI->requiresRegisterScavenging(MF) && FrameIndexVirtualScavenging)
    scavengeFrameVirtualRegs(MF, *RS);

  // Warn on stack size when we exceeds the given limit.
  MachineFrameInfo &MFI = MF.getFrameInfo();
  uint64_t StackSize = MFI.getStackSize();

  uint64_t Threshold = TFI->getStackThreshold();
  if (MF.getFunction().hasFnAttribute("warn-stack-size")) {
    bool Failed = MF.getFunction()
                      .getFnAttribute("warn-stack-size")
                      .getValueAsString()
                      .getAsInteger(10, Threshold);
    // Verifier should have caught this.
    assert(!Failed && "Invalid warn-stack-size fn attr value");
    (void)Failed;
  }
  uint64_t UnsafeStackSize = MFI.getUnsafeStackSize();
  if (MF.getFunction().hasFnAttribute(Attribute::SafeStack))
    StackSize += UnsafeStackSize;

  if (StackSize > Threshold) {
    DiagnosticInfoStackSize DiagStackSize(F, StackSize, Threshold, DS_Warning);
    F.getContext().diagnose(DiagStackSize);
    int64_t SpillSize = 0;
    for (int Idx = MFI.getObjectIndexBegin(), End = MFI.getObjectIndexEnd();
         Idx != End; ++Idx) {
      if (MFI.isSpillSlotObjectIndex(Idx))
        SpillSize += MFI.getObjectSize(Idx);
    }

    [[maybe_unused]] float SpillPct =
        static_cast<float>(SpillSize) / static_cast<float>(StackSize);
    LLVM_DEBUG(
        dbgs() << formatv("{0}/{1} ({3:P}) spills, {2}/{1} ({4:P}) variables",
                          SpillSize, StackSize, StackSize - SpillSize, SpillPct,
                          1.0f - SpillPct));
    if (UnsafeStackSize != 0) {
      LLVM_DEBUG(dbgs() << formatv(", {0}/{2} ({1:P}) unsafe stack",
                                   UnsafeStackSize,
                                   static_cast<float>(UnsafeStackSize) /
                                       static_cast<float>(StackSize),
                                   StackSize));
    }
    LLVM_DEBUG(dbgs() << "\n");
  }

  ORE->emit([&]() {
    return MachineOptimizationRemarkAnalysis(DEBUG_TYPE, "StackSize",
                                             MF.getFunction().getSubprogram(),
                                             &MF.front())
           << ore::NV("NumStackBytes", StackSize)
           << " stack bytes in function '"
           << ore::NV("Function", MF.getFunction().getName()) << "'";
  });

  // Emit any remarks implemented for the target, based on final frame layout.
  TFI->emitRemarks(MF, ORE);

  delete RS;
  SaveBlocks.clear();
  RestoreBlocks.clear();
  MFI.clearSavePoints();
  MFI.clearRestorePoints();
  return true;
}

/// runOnMachineFunction - Insert prolog/epilog code and replace abstract
/// frame indexes with appropriate references.
bool PEILegacy::runOnMachineFunction(MachineFunction &MF) {
  MachineOptimizationRemarkEmitter *ORE =
      &getAnalysis<MachineOptimizationRemarkEmitterPass>().getORE();
  return PEIImpl(ORE).run(MF);
}

PreservedAnalyses
PrologEpilogInserterPass::run(MachineFunction &MF,
                              MachineFunctionAnalysisManager &MFAM) {
  MachineOptimizationRemarkEmitter &ORE =
      MFAM.getResult<MachineOptimizationRemarkEmitterAnalysis>(MF);
  if (!PEIImpl(&ORE).run(MF))
    return PreservedAnalyses::all();

  return getMachineFunctionPassPreservedAnalyses().preserveSet<CFGAnalyses>();
}

/// Calculate the MaxCallFrameSize variable for the function's frame
/// information and eliminate call frame pseudo instructions.
void PEIImpl::calculateCallFrameInfo(MachineFunction &MF) {
  const TargetInstrInfo &TII = *MF.getSubtarget().getInstrInfo();
  const TargetFrameLowering *TFI = MF.getSubtarget().getFrameLowering();
  MachineFrameInfo &MFI = MF.getFrameInfo();

  // Get the function call frame set-up and tear-down instruction opcode
  unsigned FrameSetupOpcode = TII.getCallFrameSetupOpcode();
  unsigned FrameDestroyOpcode = TII.getCallFrameDestroyOpcode();

  // Early exit for targets which have no call frame setup/destroy pseudo
  // instructions.
  if (FrameSetupOpcode == ~0u && FrameDestroyOpcode == ~0u)
    return;

  // (Re-)Compute the MaxCallFrameSize.
  [[maybe_unused]] uint64_t MaxCFSIn =
      MFI.isMaxCallFrameSizeComputed() ? MFI.getMaxCallFrameSize() : UINT64_MAX;
  std::vector<MachineBasicBlock::iterator> FrameSDOps;
  MFI.computeMaxCallFrameSize(MF, &FrameSDOps);
  assert(MFI.getMaxCallFrameSize() <= MaxCFSIn &&
         "Recomputing MaxCFS gave a larger value.");
  assert((FrameSDOps.empty() || MF.getFrameInfo().adjustsStack()) &&
         "AdjustsStack not set in presence of a frame pseudo instruction.");

  if (TFI->canSimplifyCallFramePseudos(MF)) {
    // If call frames are not being included as part of the stack frame, and
    // the target doesn't indicate otherwise, remove the call frame pseudos
    // here. The sub/add sp instruction pairs are still inserted, but we don't
    // need to track the SP adjustment for frame index elimination.
    for (MachineBasicBlock::iterator I : FrameSDOps)
      TFI->eliminateCallFramePseudoInstr(MF, *I->getParent(), I);

    // We can't track the call frame size after call frame pseudos have been
    // eliminated. Set it to zero everywhere to keep MachineVerifier happy.
    for (MachineBasicBlock &MBB : MF)
      MBB.setCallFrameSize(0);
  }
}

/// Compute the sets of entry and return blocks for saving and restoring
/// callee-saved registers, and placing prolog and epilog code.
void PEIImpl::calculateSaveRestoreBlocks(MachineFunction &MF) {
  const MachineFrameInfo &MFI = MF.getFrameInfo();
  // Even when we do not change any CSR, we still want to insert the
  // prologue and epilogue of the function.
  // So set the save points for those.

  // Use the points found by shrink-wrapping, if any.
  if (!MFI.getSavePoints().empty()) {
    assert(MFI.getSavePoints().size() == 1 &&
           "Multiple save points are not yet supported!");
    const auto &SavePoint = *MFI.getSavePoints().begin();
    SaveBlocks.push_back(SavePoint.first);
    assert(MFI.getRestorePoints().size() == 1 &&
           "Multiple restore points are not yet supported!");
    const auto &RestorePoint = *MFI.getRestorePoints().begin();
    MachineBasicBlock *RestoreBlock = RestorePoint.first;
    // If RestoreBlock does not have any successor and is not a return block
    // then the end point is unreachable and we do not need to insert any
    // epilogue.
    if (!RestoreBlock->succ_empty() || RestoreBlock->isReturnBlock())
      RestoreBlocks.push_back(RestoreBlock);
    return;
  }

  // Save refs to entry and return blocks.
  SaveBlocks.push_back(&MF.front());
  for (MachineBasicBlock &MBB : MF) {
    if (MBB.isEHFuncletEntry())
      SaveBlocks.push_back(&MBB);
    if (MBB.isReturnBlock())
      RestoreBlocks.push_back(&MBB);
  }
}

static void assignCalleeSavedSpillSlots(MachineFunction &F,
                                        const BitVector &SavedRegs) {
  if (SavedRegs.empty())
    return;

  const TargetRegisterInfo *RegInfo = F.getSubtarget().getRegisterInfo();
  const MCPhysReg *CSRegs = F.getRegInfo().getCalleeSavedRegs();
  BitVector CSMask(SavedRegs.size());

  for (unsigned i = 0; CSRegs[i]; ++i)
    CSMask.set(CSRegs[i]);

  std::vector<CalleeSavedInfo> CSI;
  for (unsigned i = 0; CSRegs[i]; ++i) {
    unsigned Reg = CSRegs[i];
    if (SavedRegs.test(Reg)) {
      bool SavedSuper = false;
      for (const MCPhysReg &SuperReg : RegInfo->superregs(Reg)) {
        // Some backends set all aliases for some registers as saved, such as
        // Mips's $fp, so they appear in SavedRegs but not CSRegs.
        if (SavedRegs.test(SuperReg) && CSMask.test(SuperReg)) {
          SavedSuper = true;
          break;
        }
      }

      if (!SavedSuper)
        CSI.push_back(CalleeSavedInfo(Reg));
    }
  }

  const TargetFrameLowering *TFI = F.getSubtarget().getFrameLowering();
  MachineFrameInfo &MFI = F.getFrameInfo();
  if (!TFI->assignCalleeSavedSpillSlots(F, RegInfo, CSI)) {
    // If target doesn't implement this, use generic code.

    if (CSI.empty())
      return; // Early exit if no callee saved registers are modified!

    unsigned NumFixedSpillSlots;
    const TargetFrameLowering::SpillSlot *FixedSpillSlots =
        TFI->getCalleeSavedSpillSlots(NumFixedSpillSlots);

    // Now that we know which registers need to be saved and restored, allocate
    // stack slots for them.
    for (auto &CS : CSI) {
      // If the target has spilled this register to another register or already
      // handled it , we don't need to allocate a stack slot.
      if (CS.isSpilledToReg())
        continue;

      MCRegister Reg = CS.getReg();
      const TargetRegisterClass *RC = RegInfo->getMinimalPhysRegClass(Reg);

      int FrameIdx;
      if (RegInfo->hasReservedSpillSlot(F, Reg, FrameIdx)) {
        CS.setFrameIdx(FrameIdx);
        continue;
      }

      // Check to see if this physreg must be spilled to a particular stack slot
      // on this target.
      const TargetFrameLowering::SpillSlot *FixedSlot = FixedSpillSlots;
      while (FixedSlot != FixedSpillSlots + NumFixedSpillSlots &&
             FixedSlot->Reg != Reg)
        ++FixedSlot;

      unsigned Size = RegInfo->getSpillSize(*RC);
      if (FixedSlot == FixedSpillSlots + NumFixedSpillSlots) {
        // Nope, just spill it anywhere convenient.
        Align Alignment = RegInfo->getSpillAlign(*RC);
        // We may not be able to satisfy the desired alignment specification of
        // the TargetRegisterClass if the stack alignment is smaller. Use the
        // min.
        Alignment = std::min(Alignment, TFI->getStackAlign());
        FrameIdx = MFI.CreateStackObject(Size, Alignment, true, nullptr,
                                         RegInfo->getSpillStackID(*RC));
        MFI.setIsCalleeSavedObjectIndex(FrameIdx, true);
      } else {
        // Spill it to the stack where we must.
        FrameIdx = MFI.CreateFixedSpillStackObject(Size, FixedSlot->Offset);
      }

      CS.setFrameIdx(FrameIdx);
    }
  }

  MFI.setCalleeSavedInfo(CSI);
}

/// Helper function to update the liveness information for the callee-saved
/// registers.
static void updateLiveness(MachineFunction &MF) {
  MachineFrameInfo &MFI = MF.getFrameInfo();
  // Visited will contain all the basic blocks that are in the region
  // where the callee saved registers are alive:
  // - Anything that is not Save or Restore -> LiveThrough.
  // - Save -> LiveIn.
  // - Restore -> LiveOut.
  // The live-out is not attached to the block, so no need to keep
  // Restore in this set.
  SmallPtrSet<MachineBasicBlock *, 8> Visited;
  SmallVector<MachineBasicBlock *, 8> WorkList;
  MachineBasicBlock *Entry = &MF.front();

  assert(MFI.getSavePoints().size() < 2 &&
         "Multiple save points not yet supported!");
  MachineBasicBlock *Save = MFI.getSavePoints().empty()
                                ? nullptr
                                : (*MFI.getSavePoints().begin()).first;

  if (!Save)
    Save = Entry;

  if (Entry != Save) {
    WorkList.push_back(Entry);
    Visited.insert(Entry);
  }
  Visited.insert(Save);

  assert(MFI.getRestorePoints().size() < 2 &&
         "Multiple restore points not yet supported!");
  MachineBasicBlock *Restore = MFI.getRestorePoints().empty()
                                   ? nullptr
                                   : (*MFI.getRestorePoints().begin()).first;
  if (Restore)
    // By construction Restore cannot be visited, otherwise it
    // means there exists a path to Restore that does not go
    // through Save.
    WorkList.push_back(Restore);

  while (!WorkList.empty()) {
    const MachineBasicBlock *CurBB = WorkList.pop_back_val();
    // By construction, the region that is after the save point is
    // dominated by the Save and post-dominated by the Restore.
    if (CurBB == Save && Save != Restore)
      continue;
    // Enqueue all the successors not already visited.
    // Those are by construction either before Save or after Restore.
    for (MachineBasicBlock *SuccBB : CurBB->successors())
      if (Visited.insert(SuccBB).second)
        WorkList.push_back(SuccBB);
  }

  const std::vector<CalleeSavedInfo> &CSI = MFI.getCalleeSavedInfo();

  MachineRegisterInfo &MRI = MF.getRegInfo();
  for (const CalleeSavedInfo &I : CSI) {
    for (MachineBasicBlock *MBB : Visited) {
      MCRegister Reg = I.getReg();
      // Add the callee-saved register as live-in.
      // It's killed at the spill.
      if (!MRI.isReserved(Reg) && !MBB->isLiveIn(Reg))
        MBB->addLiveIn(Reg);
    }
    // If callee-saved register is spilled to another register rather than
    // spilling to stack, the destination register has to be marked as live for
    // each MBB between the prologue and epilogue so that it is not clobbered
    // before it is reloaded in the epilogue. The Visited set contains all
    // blocks outside of the region delimited by prologue/epilogue.
    if (I.isSpilledToReg()) {
      for (MachineBasicBlock &MBB : MF) {
        if (Visited.count(&MBB))
          continue;
        MCRegister DstReg = I.getDstReg();
        if (!MBB.isLiveIn(DstReg))
          MBB.addLiveIn(DstReg);
      }
    }
  }
}

/// Insert spill code for the callee-saved registers used in the function.
static void insertCSRSaves(MachineBasicBlock &SaveBlock,
                           ArrayRef<CalleeSavedInfo> CSI) {
  MachineFunction &MF = *SaveBlock.getParent();
  const TargetInstrInfo *TII = MF.getSubtarget().getInstrInfo();
  const TargetFrameLowering *TFI = MF.getSubtarget().getFrameLowering();
  const TargetRegisterInfo *TRI = MF.getSubtarget().getRegisterInfo();

  MachineBasicBlock::iterator I = SaveBlock.begin();
  if (!TFI->spillCalleeSavedRegisters(SaveBlock, I, CSI, TRI)) {
    for (const CalleeSavedInfo &CS : CSI) {
      TFI->spillCalleeSavedRegister(SaveBlock, I, CS, TII, TRI);
    }
  }
}

/// Insert restore code for the callee-saved registers used in the function.
static void insertCSRRestores(MachineBasicBlock &RestoreBlock,
                              std::vector<CalleeSavedInfo> &CSI) {
  MachineFunction &MF = *RestoreBlock.getParent();
  const TargetInstrInfo *TII = MF.getSubtarget().getInstrInfo();
  const TargetFrameLowering *TFI = MF.getSubtarget().getFrameLowering();
  const TargetRegisterInfo *TRI = MF.getSubtarget().getRegisterInfo();

  // Restore all registers immediately before the return and any
  // terminators that precede it.
  MachineBasicBlock::iterator I = RestoreBlock.getFirstTerminator();

  if (!TFI->restoreCalleeSavedRegisters(RestoreBlock, I, CSI, TRI)) {
    for (const CalleeSavedInfo &CI : reverse(CSI)) {
      TFI->restoreCalleeSavedRegister(RestoreBlock, I, CI, TII, TRI);
    }
  }
}

void PEIImpl::spillCalleeSavedRegs(MachineFunction &MF) {
  // We can't list this requirement in getRequiredProperties because some
  // targets (WebAssembly) use virtual registers past this point, and the pass
  // pipeline is set up without giving the passes a chance to look at the
  // TargetMachine.
  // FIXME: Find a way to express this in getRequiredProperties.
  assert(MF.getProperties().hasNoVRegs());

  const Function &F = MF.getFunction();
  const TargetFrameLowering *TFI = MF.getSubtarget().getFrameLowering();
  MachineFrameInfo &MFI = MF.getFrameInfo();

  // Determine which of the registers in the callee save list should be saved.
  BitVector SavedRegs;
  TFI->determineCalleeSaves(MF, SavedRegs, RS);

  // Assign stack slots for any callee-saved registers that must be spilled.
  assignCalleeSavedSpillSlots(MF, SavedRegs);

  // Add the code to save and restore the callee saved registers.
  if (!F.hasFnAttribute(Attribute::Naked)) {
    MFI.setCalleeSavedInfoValid(true);

    std::vector<CalleeSavedInfo> &CSI = MFI.getCalleeSavedInfo();

    // Fill SavePoints and RestorePoints with CalleeSavedRegisters
    if (!MFI.getSavePoints().empty()) {
      SaveRestorePoints SaveRestorePts;
      for (const auto &SavePoint : MFI.getSavePoints())
        SaveRestorePts.insert({SavePoint.first, CSI});
      MFI.setSavePoints(std::move(SaveRestorePts));

      SaveRestorePts.clear();
      for (const auto &RestorePoint : MFI.getRestorePoints())
        SaveRestorePts.insert({RestorePoint.first, CSI});
      MFI.setRestorePoints(std::move(SaveRestorePts));
    }

    if (!CSI.empty()) {
      if (!MFI.hasCalls())
        NumLeafFuncWithSpills++;

      for (MachineBasicBlock *SaveBlock : SaveBlocks)
        insertCSRSaves(*SaveBlock, CSI);

      // Update the live-in information of all the blocks up to the save point.
      updateLiveness(MF);

      for (MachineBasicBlock *RestoreBlock : RestoreBlocks)
        insertCSRRestores(*RestoreBlock, CSI);
    }
  }
}

/// AdjustStackOffset - Helper function used to adjust the stack frame offset.
static inline void AdjustStackOffset(MachineFrameInfo &MFI, int FrameIdx,
                                     bool StackGrowsDown, int64_t &Offset,
                                     Align &MaxAlign) {
  // If the stack grows down, add the object size to find the lowest address.
  if (StackGrowsDown)
    Offset += MFI.getObjectSize(FrameIdx);

  Align Alignment = MFI.getObjectAlign(FrameIdx);

  // If the alignment of this object is greater than that of the stack, then
  // increase the stack alignment to match.
  MaxAlign = std::max(MaxAlign, Alignment);

  // Adjust to alignment boundary.
  Offset = alignTo(Offset, Alignment);

  if (StackGrowsDown) {
    LLVM_DEBUG(dbgs() << "alloc FI(" << FrameIdx << ") at SP[" << -Offset
                      << "]\n");
    MFI.setObjectOffset(FrameIdx, -Offset); // Set the computed offset
  } else {
    LLVM_DEBUG(dbgs() << "alloc FI(" << FrameIdx << ") at SP[" << Offset
                      << "]\n");
    MFI.setObjectOffset(FrameIdx, Offset);
    Offset += MFI.getObjectSize(FrameIdx);
  }
}

/// Compute which bytes of fixed and callee-save stack area are unused and keep
/// track of them in StackBytesFree.
static inline void computeFreeStackSlots(MachineFrameInfo &MFI,
                                         bool StackGrowsDown,
                                         int64_t FixedCSEnd,
                                         BitVector &StackBytesFree) {
  // Avoid undefined int64_t -> int conversion below in extreme case.
  if (FixedCSEnd > std::numeric_limits<int>::max())
    return;

  StackBytesFree.resize(FixedCSEnd, true);

  SmallVector<int, 16> AllocatedFrameSlots;
  // Add fixed objects.
  for (int i = MFI.getObjectIndexBegin(); i != 0; ++i)
    // StackSlot scavenging is only implemented for the default stack.
    if (MFI.getStackID(i) == TargetStackID::Default)
      AllocatedFrameSlots.push_back(i);
  // Add callee-save objects if there are any.
  for (int i = MFI.getObjectIndexBegin(); i < MFI.getObjectIndexEnd(); i++)
    if (MFI.isCalleeSavedObjectIndex(i) &&
        MFI.getStackID(i) == TargetStackID::Default)
      AllocatedFrameSlots.push_back(i);

  for (int i : AllocatedFrameSlots) {
    // These are converted from int64_t, but they should always fit in int
    // because of the FixedCSEnd check above.
    int ObjOffset = MFI.getObjectOffset(i);
    int ObjSize = MFI.getObjectSize(i);
    int ObjStart, ObjEnd;
    if (StackGrowsDown) {
      // ObjOffset is negative when StackGrowsDown is true.
      ObjStart = -ObjOffset - ObjSize;
      ObjEnd = -ObjOffset;
    } else {
      ObjStart = ObjOffset;
      ObjEnd = ObjOffset + ObjSize;
    }
    // Ignore fixed holes that are in the previous stack frame.
    if (ObjEnd > 0)
      StackBytesFree.reset(ObjStart, ObjEnd);
  }
}

/// Assign frame object to an unused portion of the stack in the fixed stack
/// object range.  Return true if the allocation was successful.
static inline bool scavengeStackSlot(MachineFrameInfo &MFI, int FrameIdx,
                                     bool StackGrowsDown, Align MaxAlign,
                                     BitVector &StackBytesFree) {
  if (MFI.isVariableSizedObjectIndex(FrameIdx))
    return false;

  if (StackBytesFree.none()) {
    // clear it to speed up later scavengeStackSlot calls to
    // StackBytesFree.none()
    StackBytesFree.clear();
    return false;
  }

  Align ObjAlign = MFI.getObjectAlign(FrameIdx);
  if (ObjAlign > MaxAlign)
    return false;

  int64_t ObjSize = MFI.getObjectSize(FrameIdx);
  int FreeStart;
  for (FreeStart = StackBytesFree.find_first(); FreeStart != -1;
       FreeStart = StackBytesFree.find_next(FreeStart)) {

    // Check that free space has suitable alignment.
    unsigned ObjStart = StackGrowsDown ? FreeStart + ObjSize : FreeStart;
    if (alignTo(ObjStart, ObjAlign) != ObjStart)
      continue;

    if (FreeStart + ObjSize > StackBytesFree.size())
      return false;

    bool AllBytesFree = true;
    for (unsigned Byte = 0; Byte < ObjSize; ++Byte)
      if (!StackBytesFree.test(FreeStart + Byte)) {
        AllBytesFree = false;
        break;
      }
    if (AllBytesFree)
      break;
  }

  if (FreeStart == -1)
    return false;

  if (StackGrowsDown) {
    int ObjStart = -(FreeStart + ObjSize);
    LLVM_DEBUG(dbgs() << "alloc FI(" << FrameIdx << ") scavenged at SP["
                      << ObjStart << "]\n");
    MFI.setObjectOffset(FrameIdx, ObjStart);
  } else {
    LLVM_DEBUG(dbgs() << "alloc FI(" << FrameIdx << ") scavenged at SP["
                      << FreeStart << "]\n");
    MFI.setObjectOffset(FrameIdx, FreeStart);
  }

  StackBytesFree.reset(FreeStart, FreeStart + ObjSize);
  return true;
}

/// AssignProtectedObjSet - Helper function to assign large stack objects (i.e.,
/// those required to be close to the Stack Protector) to stack offsets.
static void AssignProtectedObjSet(const StackObjSet &UnassignedObjs,
                                  SmallSet<int, 16> &ProtectedObjs,
                                  MachineFrameInfo &MFI, bool StackGrowsDown,
                                  int64_t &Offset, Align &MaxAlign) {

  for (int i : UnassignedObjs) {
    AdjustStackOffset(MFI, i, StackGrowsDown, Offset, MaxAlign);
    ProtectedObjs.insert(i);
  }
}

/// calculateFrameObjectOffsets - Calculate actual frame offsets for all of the
/// abstract stack objects.
void PEIImpl::calculateFrameObjectOffsets(MachineFunction &MF) {
  const TargetFrameLowering &TFI = *MF.getSubtarget().getFrameLowering();

  bool StackGrowsDown =
    TFI.getStackGrowthDirection() == TargetFrameLowering::StackGrowsDown;

  // Loop over all of the stack objects, assigning sequential addresses...
  MachineFrameInfo &MFI = MF.getFrameInfo();

  // Start at the beginning of the local area.
  // The Offset is the distance from the stack top in the direction
  // of stack growth -- so it's always nonnegative.
  int LocalAreaOffset = TFI.getOffsetOfLocalArea();
  if (StackGrowsDown)
    LocalAreaOffset = -LocalAreaOffset;
  assert(LocalAreaOffset >= 0
         && "Local area offset should be in direction of stack growth");
  int64_t Offset = LocalAreaOffset;

#ifdef EXPENSIVE_CHECKS
  for (unsigned i = 0, e = MFI.getObjectIndexEnd(); i != e; ++i)
    if (!MFI.isDeadObjectIndex(i) &&
        MFI.getStackID(i) == TargetStackID::Default)
      assert(MFI.getObjectAlign(i) <= MFI.getMaxAlign() &&
             "MaxAlignment is invalid");
#endif

  // If there are fixed sized objects that are preallocated in the local area,
  // non-fixed objects can't be allocated right at the start of local area.
  // Adjust 'Offset' to point to the end of last fixed sized preallocated
  // object.
  for (int i = MFI.getObjectIndexBegin(); i != 0; ++i) {
    // Only allocate objects on the default stack.
    if (MFI.getStackID(i) != TargetStackID::Default)
      continue;

    int64_t FixedOff;
    if (StackGrowsDown) {
      // The maximum distance from the stack pointer is at lower address of
      // the object -- which is given by offset. For down growing stack
      // the offset is negative, so we negate the offset to get the distance.
      FixedOff = -MFI.getObjectOffset(i);
    } else {
      // The maximum distance from the start pointer is at the upper
      // address of the object.
      FixedOff = MFI.getObjectOffset(i) + MFI.getObjectSize(i);
    }
    if (FixedOff > Offset) Offset = FixedOff;
  }

  Align MaxAlign = MFI.getMaxAlign();
  // First assign frame offsets to stack objects that are used to spill
  // callee saved registers.
  auto AllFIs = seq(MFI.getObjectIndexBegin(), MFI.getObjectIndexEnd());
  for (int FI : reverse_conditionally(AllFIs, /*Reverse=*/!StackGrowsDown)) {
    // Only allocate objects on the default stack.
    if (!MFI.isCalleeSavedObjectIndex(FI) ||
        MFI.getStackID(FI) != TargetStackID::Default)
      continue;

    // TODO: should this just be if (MFI.isDeadObjectIndex(FI))
    if (!StackGrowsDown && MFI.isDeadObjectIndex(FI))
      continue;

    AdjustStackOffset(MFI, FI, StackGrowsDown, Offset, MaxAlign);
  }

  assert(MaxAlign == MFI.getMaxAlign() &&
         "MFI.getMaxAlign should already account for all callee-saved "
         "registers without a fixed stack slot");

  // FixedCSEnd is the stack offset to the end of the fixed and callee-save
  // stack area.
  int64_t FixedCSEnd = Offset;

  // Make sure the special register scavenging spill slot is closest to the
  // incoming stack pointer if a frame pointer is required and is closer
  // to the incoming rather than the final stack pointer.
  const TargetRegisterInfo *RegInfo = MF.getSubtarget().getRegisterInfo();
  bool EarlyScavengingSlots = TFI.allocateScavengingFrameIndexesNearIncomingSP(MF);
  if (RS && EarlyScavengingSlots) {
    SmallVector<int, 2> SFIs;
    RS->getScavengingFrameIndices(SFIs);
    for (int SFI : SFIs)
      AdjustStackOffset(MFI, SFI, StackGrowsDown, Offset, MaxAlign);
  }

  // FIXME: Once this is working, then enable flag will change to a target
  // check for whether the frame is large enough to want to use virtual
  // frame index registers. Functions which don't want/need this optimization
  // will continue to use the existing code path.
  if (MFI.getUseLocalStackAllocationBlock()) {
    Align Alignment = MFI.getLocalFrameMaxAlign();

    // Adjust to alignment boundary.
    Offset = alignTo(Offset, Alignment);

    LLVM_DEBUG(dbgs() << "Local frame base offset: " << Offset << "\n");

    // Resolve offsets for objects in the local block.
    for (unsigned i = 0, e = MFI.getLocalFrameObjectCount(); i != e; ++i) {
      std::pair<int, int64_t> Entry = MFI.getLocalFrameObjectMap(i);
      int64_t FIOffset = (StackGrowsDown ? -Offset : Offset) + Entry.second;
      LLVM_DEBUG(dbgs() << "alloc FI(" << Entry.first << ") at SP[" << FIOffset
                        << "]\n");
      MFI.setObjectOffset(Entry.first, FIOffset);
    }
    // Allocate the local block
    Offset += MFI.getLocalFrameSize();

    MaxAlign = std::max(Alignment, MaxAlign);
  }

  // Retrieve the Exception Handler registration node.
  int EHRegNodeFrameIndex = std::numeric_limits<int>::max();
  if (const WinEHFuncInfo *FuncInfo = MF.getWinEHFuncInfo())
    EHRegNodeFrameIndex = FuncInfo->EHRegNodeFrameIndex;

  // Make sure that the stack protector comes before the local variables on the
  // stack.
  SmallSet<int, 16> ProtectedObjs;
  if (MFI.hasStackProtectorIndex()) {
    int StackProtectorFI = MFI.getStackProtectorIndex();
    StackObjSet LargeArrayObjs;
    StackObjSet SmallArrayObjs;
    StackObjSet AddrOfObjs;

    // If we need a stack protector, we need to make sure that
    // LocalStackSlotPass didn't already allocate a slot for it.
    // If we are told to use the LocalStackAllocationBlock, the stack protector
    // is expected to be already pre-allocated.
    if (MFI.getStackID(StackProtectorFI) != TargetStackID::Default) {
      // If the stack protector isn't on the default stack then it's up to the
      // target to set the stack offset.
      assert(MFI.getObjectOffset(StackProtectorFI) != 0 &&
             "Offset of stack protector on non-default stack expected to be "
             "already set.");
      assert(!MFI.isObjectPreAllocated(MFI.getStackProtectorIndex()) &&
             "Stack protector on non-default stack expected to not be "
             "pre-allocated by LocalStackSlotPass.");
    } else if (!MFI.getUseLocalStackAllocationBlock()) {
      AdjustStackOffset(MFI, StackProtectorFI, StackGrowsDown, Offset,
                        MaxAlign);
    } else if (!MFI.isObjectPreAllocated(MFI.getStackProtectorIndex())) {
      llvm_unreachable(
          "Stack protector not pre-allocated by LocalStackSlotPass.");
    }

    // Assign large stack objects first.
    for (unsigned i = 0, e = MFI.getObjectIndexEnd(); i != e; ++i) {
      if (MFI.isObjectPreAllocated(i) && MFI.getUseLocalStackAllocationBlock())
        continue;
      if (MFI.isCalleeSavedObjectIndex(i))
        continue;
      if (RS && RS->isScavengingFrameIndex((int)i))
        continue;
      if (MFI.isDeadObjectIndex(i))
        continue;
      if (StackProtectorFI == (int)i || EHRegNodeFrameIndex == (int)i)
        continue;
      // Only allocate objects on the default stack.
      if (MFI.getStackID(i) != TargetStackID::Default)
        continue;

      switch (MFI.getObjectSSPLayout(i)) {
      case MachineFrameInfo::SSPLK_None:
        continue;
      case MachineFrameInfo::SSPLK_SmallArray:
        SmallArrayObjs.insert(i);
        continue;
      case MachineFrameInfo::SSPLK_AddrOf:
        AddrOfObjs.insert(i);
        continue;
      case MachineFrameInfo::SSPLK_LargeArray:
        LargeArrayObjs.insert(i);
        continue;
      }
      llvm_unreachable("Unexpected SSPLayoutKind.");
    }

    // We expect **all** the protected stack objects to be pre-allocated by
    // LocalStackSlotPass. If it turns out that PEI still has to allocate some
    // of them, we may end up messing up the expected order of the objects.
    if (MFI.getUseLocalStackAllocationBlock() &&
        !(LargeArrayObjs.empty() && SmallArrayObjs.empty() &&
          AddrOfObjs.empty()))
      llvm_unreachable("Found protected stack objects not pre-allocated by "
                       "LocalStackSlotPass.");

    AssignProtectedObjSet(LargeArrayObjs, ProtectedObjs, MFI, StackGrowsDown,
                          Offset, MaxAlign);
    AssignProtectedObjSet(SmallArrayObjs, ProtectedObjs, MFI, StackGrowsDown,
                          Offset, MaxAlign);
    AssignProtectedObjSet(AddrOfObjs, ProtectedObjs, MFI, StackGrowsDown,
                          Offset, MaxAlign);
  }

  SmallVector<int, 8> ObjectsToAllocate;

  // Then prepare to assign frame offsets to stack objects that are not used to
  // spill callee saved registers.
  for (unsigned i = 0, e = MFI.getObjectIndexEnd(); i != e; ++i) {
    if (MFI.isObjectPreAllocated(i) && MFI.getUseLocalStackAllocationBlock())
      continue;
    if (MFI.isCalleeSavedObjectIndex(i))
      continue;
    if (RS && RS->isScavengingFrameIndex((int)i))
      continue;
    if (MFI.isDeadObjectIndex(i))
      continue;
    if (MFI.getStackProtectorIndex() == (int)i || EHRegNodeFrameIndex == (int)i)
      continue;
    if (ProtectedObjs.count(i))
      continue;
    // Only allocate objects on the default stack.
    if (MFI.getStackID(i) != TargetStackID::Default)
      continue;

    // Add the objects that we need to allocate to our working set.
    ObjectsToAllocate.push_back(i);
  }

  // Allocate the EH registration node first if one is present.
  if (EHRegNodeFrameIndex != std::numeric_limits<int>::max())
    AdjustStackOffset(MFI, EHRegNodeFrameIndex, StackGrowsDown, Offset,
                      MaxAlign);

  // Give the targets a chance to order the objects the way they like it.
  if (MF.getTarget().getOptLevel() != CodeGenOptLevel::None &&
      MF.getTarget().Options.StackSymbolOrdering)
    TFI.orderFrameObjects(MF, ObjectsToAllocate);

  // Keep track of which bytes in the fixed and callee-save range are used so we
  // can use the holes when allocating later stack objects.  Only do this if
  // stack protector isn't being used and the target requests it and we're
  // optimizing.
  BitVector StackBytesFree;
  if (!ObjectsToAllocate.empty() &&
      MF.getTarget().getOptLevel() != CodeGenOptLevel::None &&
      MFI.getStackProtectorIndex() < 0 && TFI.enableStackSlotScavenging(MF))
    computeFreeStackSlots(MFI, StackGrowsDown, FixedCSEnd, StackBytesFree);

  // Now walk the objects and actually assign base offsets to them.
  for (auto &Object : ObjectsToAllocate)
    if (!scavengeStackSlot(MFI, Object, StackGrowsDown, MaxAlign,
                           StackBytesFree))
      AdjustStackOffset(MFI, Object, StackGrowsDown, Offset, MaxAlign);

  // Make sure the special register scavenging spill slot is closest to the
  // stack pointer.
  if (RS && !EarlyScavengingSlots) {
    SmallVector<int, 2> SFIs;
    RS->getScavengingFrameIndices(SFIs);
    for (int SFI : SFIs)
      AdjustStackOffset(MFI, SFI, StackGrowsDown, Offset, MaxAlign);
  }

  if (!TFI.targetHandlesStackFrameRounding()) {
    // If we have reserved argument space for call sites in the function
    // immediately on entry to the current function, count it as part of the
    // overall stack size.
    if (MFI.adjustsStack() && TFI.hasReservedCallFrame(MF))
      Offset += MFI.getMaxCallFrameSize();

    // Round up the size to a multiple of the alignment.  If the function has
    // any calls or alloca's, align to the target's StackAlignment value to
    // ensure that the callee's frame or the alloca data is suitably aligned;
    // otherwise, for leaf functions, align to the TransientStackAlignment
    // value.
    Align StackAlign;
    if (MFI.adjustsStack() || MFI.hasVarSizedObjects() ||
        (RegInfo->hasStackRealignment(MF) && MFI.getObjectIndexEnd() != 0))
      StackAlign = TFI.getStackAlign();
    else
      StackAlign = TFI.getTransientStackAlign();

    // If the frame pointer is eliminated, all frame offsets will be relative to
    // SP not FP. Align to MaxAlign so this works.
    StackAlign = std::max(StackAlign, MaxAlign);
    int64_t OffsetBeforeAlignment = Offset;
    Offset = alignTo(Offset, StackAlign);

    // If we have increased the offset to fulfill the alignment constrants,
    // then the scavenging spill slots may become harder to reach from the
    // stack pointer, float them so they stay close.
    if (StackGrowsDown && OffsetBeforeAlignment != Offset && RS &&
        !EarlyScavengingSlots) {
      SmallVector<int, 2> SFIs;
      RS->getScavengingFrameIndices(SFIs);
      LLVM_DEBUG(if (!SFIs.empty()) llvm::dbgs()
                     << "Adjusting emergency spill slots!\n";);
      int64_t Delta = Offset - OffsetBeforeAlignment;
      for (int SFI : SFIs) {
        LLVM_DEBUG(llvm::dbgs()
                       << "Adjusting offset of emergency spill slot #" << SFI
                       << " from " << MFI.getObjectOffset(SFI););
        MFI.setObjectOffset(SFI, MFI.getObjectOffset(SFI) - Delta);
        LLVM_DEBUG(llvm::dbgs() << " to " << MFI.getObjectOffset(SFI) << "\n";);
      }
    }
  }

  // Update frame info to pretend that this is part of the stack...
  int64_t StackSize = Offset - LocalAreaOffset;
  MFI.setStackSize(StackSize);
  NumBytesStackSpace += StackSize;
}

/// insertPrologEpilogCode - Scan the function for modified callee saved
/// registers, insert spill code for these callee saved registers, then add
/// prolog and epilog code to the function.
void PEIImpl::insertPrologEpilogCode(MachineFunction &MF) {
  const TargetFrameLowering &TFI = *MF.getSubtarget().getFrameLowering();

  // Add prologue to the function...
  for (MachineBasicBlock *SaveBlock : SaveBlocks)
    TFI.emitPrologue(MF, *SaveBlock);

  // Add epilogue to restore the callee-save registers in each exiting block.
  for (MachineBasicBlock *RestoreBlock : RestoreBlocks)
    TFI.emitEpilogue(MF, *RestoreBlock);

  // This is the point at which clearing is enforced: registers are allocated,
  // the frame is laid out, and frame indices have not been eliminated yet. Run
  // the clearing sequence at every exit that is in scope.
  insertClearingSequences(MF);

  for (MachineBasicBlock *SaveBlock : SaveBlocks)
    TFI.inlineStackProbe(MF, *SaveBlock);

  // Emit additional code that is required to support segmented stacks, if
  // we've been asked for it.  This, when linked with a runtime with support
  // for segmented stacks (libgcc is one), will result in allocating stack
  // space in small chunks instead of one large contiguous block.
  if (MF.shouldSplitStack()) {
    for (MachineBasicBlock *SaveBlock : SaveBlocks)
      TFI.adjustForSegmentedStacks(MF, *SaveBlock);
  }

  // Emit additional code that is required to explicitly handle the stack in
  // HiPE native code (if needed) when loaded in the Erlang/OTP runtime. The
  // approach is rather similar to that of Segmented Stacks, but it uses a
  // different conditional check and another BIF for allocating more stack
  // space.
  if (MF.getFunction().getCallingConv() == CallingConv::HiPE)
    for (MachineBasicBlock *SaveBlock : SaveBlocks)
      TFI.adjustForHiPEPrologue(MF, *SaveBlock);
}

/// The clearing "zero-call-used-regs" asks for. No attribute means Skip.
static ZeroCallUsedRegs::ZeroCallUsedRegsKind
getZeroCallUsedRegsKind(const Function &F) {
  using namespace ZeroCallUsedRegs;

  if (!F.hasFnAttribute("zero-call-used-regs"))
    return ZeroCallUsedRegsKind::Skip;

  return StringSwitch<ZeroCallUsedRegsKind>(
             F.getFnAttribute("zero-call-used-regs").getValueAsString())
      .Case("skip", ZeroCallUsedRegsKind::Skip)
      .Case("used-gpr-arg", ZeroCallUsedRegsKind::UsedGPRArg)
      .Case("used-gpr", ZeroCallUsedRegsKind::UsedGPR)
      .Case("used-arg", ZeroCallUsedRegsKind::UsedArg)
      .Case("used", ZeroCallUsedRegsKind::Used)
      .Case("all-gpr-arg", ZeroCallUsedRegsKind::AllGPRArg)
      .Case("all-gpr", ZeroCallUsedRegsKind::AllGPR)
      .Case("all-arg", ZeroCallUsedRegsKind::AllArg)
      .Case("all", ZeroCallUsedRegsKind::All)
      // A mode this version of LLVM does not recognize means the widest
      // one. The modes are a scale from "skip" to "all", and a name off
      // the end of what is known here is either a mode added later, whose
      // author selected it over the ones that already existed, or a
      // mistake. "all" is the only answer that is safe under both
      // readings, and it is the reading LangRef already fixes for an
      // unrecognized "zeroize-stack" mode.
      //
      // Without this the switch runs off its end: an assertion in a build
      // that has them, and in a release compiler an uninitialized mode
      // that decides what gets cleared. Neither is a decision.
      .Default(ZeroCallUsedRegsKind::All);
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

/// The instruction control leaves \p MBB through, if a clearing sequence can be
/// placed at it, or null if it cannot. Only what the exit does with the frame
/// decides this.
///
/// A block with a successor continues in the function, so it is never an exit,
/// and that is tested first. isReturn alone is not enough: catchret carries it
/// but only leaves the exception scope, resuming the function at the block it
/// names, so its registers are still the function's and clearing belongs at the
/// real exit downstream. Clearing at it would also destroy the resumption
/// address the funclet ABI returns.
///
/// Otherwise a return block is the whole of it: plain return, tail call and
/// cleanupret-to-caller all carry isReturn, and the usual return-block walk
/// reaches them. The one it misses is a landing pad that resumes unwinding by a
/// call, not a return; no existing predicate reaches it, so this does.
///
/// The exits this returns null for are out of scope rather than overlooked, and
/// for the same reason in each case: the frame is abandoned rather than
/// released, so there is no position at which a sequence could run and still be
/// the last thing to touch it. A call that does not return here hands the
/// caller's context back through the unwinder or through a jump with nothing of
/// ours in between; a non-local jump does the same by reloading another frame's
/// stack and frame pointers; and a trap, or an empty block left behind by an
/// unreachable, does not transfer out of the frame at all.
///
/// A block that ends in none of those is in scope, not out of it. Failing to
/// recognise an instruction is not the same as knowing what it does, and the
/// two errors are not symmetric: an opaque instruction that does leave the
/// function takes the frame and the registers with it, while one that does not
/// costs a dead sequence in a block nothing reaches. The uncertainty is
/// resolved towards clearing.
static MachineInstr *getEnforceableExit(MachineBasicBlock &MBB) {
  // A block with a successor continues in the function, so it is not an exit
  // however its terminator reads; catchret reaches here carrying isReturn.
  if (!MBB.succ_empty())
    return nullptr;

  if (MBB.isReturnBlock())
    return &*MBB.getFirstTerminator();

  // Labels, CFI and the rest of the meta instructions carry no control flow, so
  // the shape of the exit is decided by what is underneath them.
  for (MachineInstr &MI : reverse(MBB.instrs())) {
    if (MI.isMetaInstruction())
      continue;

    // A call either resumes unwinding, which is an exit a sequence goes in
    // front of, or does not come back here at all, which abandons the frame.
    if (MI.isCall())
      return isUnwindResumeCall(MI) ? &MI : nullptr;

    // A jump with no successor in this function is a jump out of it. Targets
    // spell a longjmp either as an indirect branch, once the jump buffer has
    // been reloaded, or as a barrier pseudo that expands to one later.
    if (MI.isIndirectBranch() ||
        (MI.isTerminator() && MI.isBarrier() && !MI.isBranch()))
      return nullptr;

    // A trap is where control stops, not where it goes: the target has said so
    // by marking the instruction, and it is the one shape left here that can be
    // ruled out rather than merely not recognised.
    if (MI.getDesc().isTrap())
      return nullptr;

    // Nothing else is known about this block, and not knowing has to be
    // recorded as not knowing. Inline assembly can jump, can issue a system
    // call that does not come back, and can return into another frame, and
    // nothing here can establish that it does not; calling such a block one
    // control stops in is the one answer that leaves the frame alone.
    return &MI;
  }

  // A block with nothing left in it has nothing that could transfer anywhere.
  return nullptr;
}

/// A short stable name for the exit \p ExitMI leaves through, for the print
/// only. The emission does not classify exits; it only needs their position,
/// which getEnforceableExit() gives.
static StringRef getExitKindName(const MachineInstr &ExitMI) {
  if (ExitMI.isEHScopeReturn())
    return "eh-scope-return";
  if (ExitMI.isReturn())
    return ExitMI.isCall() ? "tail-call" : "return";
  if (ExitMI.isCall())
    return "unwind-resume";
  return "unknown";
}

/// Where the clearing sequence goes at \p ExitMI of \p MBB. Every step emits
/// here, so the emit order is the run order. At an exit that leaves through a
/// terminator it goes in front of the first terminator (after the epilogue,
/// where register clearing has always gone). An exit that leaves through a call,
/// one that resumes unwinding, has no terminator, so it goes in front of the
/// call: after it is after the function.
static MachineBasicBlock::iterator
getClearingInsertPoint(MachineBasicBlock &MBB, MachineInstr &ExitMI) {
  if (ExitMI.isTerminator())
    return MBB.getFirstTerminator();
  return MachineBasicBlock::iterator(ExitMI);
}

/// The registers to clear at this exit, from the candidates \p Candidates the
/// mode allows. What an exit still needs is the exit's to decide, not the
/// function's. The sequence is emitted at \p InsertPt, so what runs after it is
/// the rest of \p MBB: a return and its return-value registers, a tail call and
/// its outgoing-argument registers, or an unwind-resume call and the argument
/// register holding the exception object. Those are spared; the rest of the
/// mode's set is dead here and cleared.
///
/// Asking the exit is what makes the answer per-exit. The old function-wide set
/// took the union over the returns instead, leaving each return's live-out
/// registers uncleared at every other return, dead and holding a value.
static BitVector computeRegsToClearAtExit(
    const BitVector &Candidates, const MachineBasicBlock &MBB,
    MachineBasicBlock::const_iterator InsertPt, const TargetRegisterInfo &TRI) {
  // Only the rest of the block runs after the sequence, and only because the
  // block does not continue in the function; getEnforceableExit() ensures that.
  assert(MBB.succ_empty() && "exit block continues in the function");

  BitVector RegsToZero = Candidates;

  for (const MachineInstr &MI : make_range(InsertPt, MBB.end())) {
    for (const MachineOperand &MO : MI.operands()) {
      if (!MO.isReg())
        continue;

      MCRegister Reg = MO.getReg();
      if (!Reg)
        continue;

      // This picks up sibling registers (e.g. %al -> %ah).
      // FIXME: mixing physical registers and register units is likely a bug,
      // and it does over-spare (a dead sibling can survive a clear). Kept all
      // the same: it also spares siblings a clear would widen into a live
      // register (%ah into %al on x86), and no target-agnostic rule keeps both
      // that and AArch64's independently-cleared register tuples correct.
      if (MI.isReturn())
        for (MCRegUnit Unit : TRI.regunits(Reg))
          RegsToZero.reset(static_cast<unsigned>(Unit));

      for (MCPhysReg SReg : TRI.sub_and_superregs_inclusive(Reg))
        RegsToZero.reset(SReg);
    }
  }

  return RegsToZero;
}

//===----------------------------------------------------------------------===//
// Scratch registers.
//
// A step of the sequence that needs registers to do its work is not the last
// word on them. Clearing the frame reads the frame through a register and
// writes zeroes back through another, so when it finishes, the registers it
// worked through hold what it has just destroyed: the value it overwrote, or
// the address inside the frame it overwrote it at. Those are the frame's
// contents by another name, and leaving with them in registers discloses
// exactly what leaving with them on the stack would have.
//
// Running the register clear after the stack clear is what makes destroying
// them possible, and ClearingSequence already fixes that order. Order alone is
// not coverage. What the register clear clears is chosen by the function's
// "zero-call-used-regs" mode, and every mode is a statement about the
// function: which registers it used, which of them are argument registers,
// which are general purpose. A register the clearing machinery dirtied is none
// of those things. A "used" mode does not select it, because the sweep that
// computes the used set runs while the plan is made, before the stack clear
// has been emitted, and so cannot see it. An "arg" mode does not select it
// unless it happens to be an argument register. And a function that asked for
// its frame to be cleared need not have asked for its registers to be cleared
// at all, in which case there is no mode to select anything.
//
// So the coverage cannot be inferred from the function, and is declared by the
// step instead: a step records the registers it used, and the register clear
// adds what has been recorded to what it was already going to clear. Two
// things follow, and both are the point rather than a side effect:
//
//  - The declaration is per exit. A step is emitted once at each in-scope exit
//    and need not use the same registers at each one, so the record is built
//    as the sequence runs at an exit and read by the register clear at that
//    same exit.
//
//  - The register clear stops being optional once a step in front of it
//    declares anything. A function with "zeroize-stack" and no
//    "zero-call-used-regs" gets one anyway, over nothing but the declared
//    registers: the request to clear the frame is not discharged while the
//    frame's contents are sitting in registers. It is also why a target that
//    cannot clear registers cannot clear the frame either, and is told so.
//
// A step may only declare a register whose value at the exit nothing depends
// on. That rules out the registers the exit itself needs -- the return value,
// a tail call's outgoing arguments, the exception object an unwind resume is
// passed -- and it rules out the callee-saved registers, which have to reach
// the exit holding what the caller left in them whether or not the exit names
// them. A step that needs such a register has to save and restore it rather
// than declare it, because what is declared is cleared. Builds with assertions
// check both halves; a build without them clears what it was told to, which is
// the direction the rest of this machinery errs in too.
//===----------------------------------------------------------------------===//

/// The register named \p Name on this target, or a null register if it has no
/// register of that name.
static MCRegister findRegisterByName(const TargetRegisterInfo &TRI,
                                     StringRef Name) {
  for (unsigned Reg = 1, E = TRI.getNumRegs(); Reg != E; ++Reg)
    if (Name.equals_insensitive(TRI.getName(Reg)))
      return MCRegister(Reg);
  return MCRegister();
}

/// Record in \p ScratchRegs the registers the ClearStack step used at this
/// exit.
///
/// It used none: no target clears the frame, so the step emits nothing
/// (trailofbits/vspells-ct-internal-notes#26). What is declared here is what
/// -pei-stack-clear-scratch-regs names, which is how the declaration and its
/// consumption are exercised while the step that would make one does not
/// exist. An implementation of the step declares what it actually used, in
/// place of this.
static void declareStackClearScratchRegs(const TargetRegisterInfo &TRI,
                                         BitVector &ScratchRegs) {
  for (const std::string &Name : StandInStackScratchRegs) {
    MCRegister Reg = findRegisterByName(TRI, Name);
    if (!Reg)
      report_fatal_error(Twine("unknown register name in "
                               "-pei-stack-clear-scratch-regs: '") +
                         Name + "'");
    ScratchRegs.set(Reg.id());
  }
}

#ifndef NDEBUG
/// Whether \p Regs holds a register whose value at the exit something depends
/// on, and which therefore cannot be declared as scratch by a step of the
/// sequence.
static bool anyRegNeededAtExit(const BitVector &Regs,
                               const MachineBasicBlock &MBB,
                               MachineBasicBlock::const_iterator InsertPt,
                               const TargetRegisterInfo &TRI) {
  const MachineFunction &MF = *MBB.getParent();

  // A callee-saved register has to reach every exit holding what the caller
  // left in it. Nothing at the exit names it, so the scan below would not find
  // it.
  for (const MCPhysReg *CSRegs = TRI.getCalleeSavedRegs(&MF);
       MCPhysReg CSReg = *CSRegs; ++CSRegs)
    for (MCRegister Reg : TRI.sub_and_superregs_inclusive(CSReg))
      if (Regs.test(Reg.id()))
        return true;

  // What the exit needs is what the instructions after the sequence read or
  // write, which is the same question computeRegsToClearAtExit answers for the
  // candidate set.
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
#endif

//===----------------------------------------------------------------------===//
// Keeping the clears.
//
// A register clear is an instruction whose only effect is to overwrite a
// register nothing reads afterwards, which is the definition of dead code. It
// is emitted precisely because nothing reads the register: the value being
// destroyed is one the function is finished with, and if anything still needed
// it the clear would be wrong. So the machine-level reason to keep it is
// missing from the instruction itself, and it survives only for as long as
// nothing looks. This is the machine-level counterpart of the non-removability
// the llvm.zeroize intrinsic already carries in the IR; an intrinsic's
// properties stop meaning anything once it has been lowered to an XOR.
//
// What supplies the missing reason is the exit. Recording the cleared
// registers as used at the point control leaves says what is in fact true:
// their values at the point of leaving are part of what the function leaves
// behind, so an instruction that sets them has an effect that outlives the
// function. A pass that removes an instruction because its definitions are
// dead then finds them live, and leaves the clear alone.
//
// The registers are named as implicit uses of the return, and only of a
// return. The other in-scope exits leave through a call or through an
// instruction the classification could not read, and neither is a place to
// state what the function leaves behind: a call's register operands describe
// its arguments and an opaque instruction's describe whatever the target or
// the asm string put there. The clears at those exits stay as they are.
//
// A register operand on an exit is not read only as liveness, which is why the
// target gets a say in which register is named: see
// TargetFrameLowering::getClearedRegExitAnchor. On X86 the collision is not
// hypothetical. The pass that inserts vzeroupper treats a return naming a YMM
// or ZMM register as a return that carries a vector value and skips the
// vzeroupper in front of it, so naming a cleared YMM there drops the
// vzeroupper from an AVX function that clears its registers and leaves the
// caller an AVX-to-SSE transition to pay. X86 answers with the 128-bit part of
// the register instead, which keeps the definition live -- a definition is
// live as soon as any part of it is -- and says nothing about vector state.
//
// An extra instruction was tried in place of the operands and does not work.
// FAKE_USE is the pseudo for exactly this ("represents a use of the operand
// but generates no code"), it is explicitly exempted from
// MachineInstr::wouldBeTriviallyDead, and it would work at every exit rather
// than only at returns. But it is not free of output: the asm printer writes a
// "# fake_use:" comment for it, so every function that clears registers grows
// a line, and a dozen existing tests read the emitted code line by line.
// Recording the fact on an instruction that is already there costs nothing.
//
// isBarrier is not the mechanism for this, and was considered and rejected. It
// says that control does not fall through the instruction -- Target.td spells
// the field "Can control flow fall through this instruction?" -- which is a
// statement about the CFG and is what makes an unconditional branch different
// from a conditional one. It has nothing to say about whether an instruction's
// effects can be discarded, it would be false of a clear in any case, and
// setting it would misdescribe the block to everything that reads it.
//
// The exposure this closes is narrower than it looks, and saying so is part of
// the change. DeadMachineInstructionElim is the pass that removes instructions
// on exactly these grounds, and in the default pipeline it runs twice, both
// times in addMachineSSAOptimization, which is before register allocation and
// so long before this. Nothing after prologue/epilogue insertion runs it: the
// passes that follow are MachineLateInstrsCleanup, BranchFolder,
// TailDuplicate, MachineCopyPropagation, the post-RA expansions and
// schedulers, block placement and the target's pre-emit passes, and none of
// them removes an instruction for having no live definitions.
// MachineLateInstrsCleanup comes closest, and it declines an XOR before
// reaching the question: its candidate test rejects an instruction that reads
// a register other than the frame register, which the two operands of the XOR
// are.
//
// So this is not a fix for something the compiler does today. It is the
// property being made to hold rather than being left to the pipeline's
// composition, and the difference is easy to see: run the pass that would
// remove them over the code this emits and, before this change, every clear in
// a function goes.
//===----------------------------------------------------------------------===//

/// Record the registers \p ClearedRegs the sequence cleared at \p ExitMI as
/// implicit uses of the return control leaves through, so that the clears are
/// observably live and cannot be removed for having no live definitions.
static void anchorClearedRegsAtExit(MachineBasicBlock &MBB,
                                    const MachineInstr &ExitMI,
                                    const BitVector &ClearedRegs,
                                    const TargetFrameLowering &TFI) {
  if (ClearedRegs.none() || !ExitMI.isReturn())
    return;

  const MachineFunction &MF = *MBB.getParent();

  for (MachineInstr &MI : MBB.terminators()) {
    if (&MI != &ExitMI)
      continue;
    for (unsigned Reg : ClearedRegs.set_bits()) {
      MCRegister Anchor = TFI.getClearedRegExitAnchor(MF, MCRegister(Reg));
      if (Anchor && !MI.hasRegisterImplicitUseOperand(Anchor))
        MI.addOperand(MachineOperand::CreateReg(Anchor, /*isDef=*/false,
                                                /*isImp=*/true));
    }
    return;
  }
}

/// insertClearingSequences - Run the clearing sequence at every exit of \p MF
/// that is in scope.
///
/// This is the one place the steps are ordered and the one place they are
/// emitted; see the comment on ClearingSequence for what the order is and why.
void PEIImpl::insertClearingSequences(MachineFunction &MF) {
  // Plan once for the function: which steps run cannot depend on the exit, or
  // the sequence would not be one sequence (what a step covers can, and the
  // register clear settles that per exit). Planning before emission also
  // reports a request the target cannot discharge whether or not the function
  // has an exit to emit at.
  ExitClearingPlan Plan;
  planClearingSequence(MF, Plan);

  if (!Plan.anyStepEmits() && !PrintClearingSequence)
    return;

  const TargetRegisterInfo &TRI = *MF.getSubtarget().getRegisterInfo();
  const TargetFrameLowering &TFI = *MF.getSubtarget().getFrameLowering();

  raw_ostream &OS = errs();
  if (PrintClearingSequence)
    OS << "clearing sequence for function '" << MF.getName() << "':\n";

  for (MachineBasicBlock &MBB : MF) {
    // Where the sequence runs is decided in one place, for every step, so
    // that a step cannot go looking for sites of its own.
    MachineInstr *ExitMI = getEnforceableExit(MBB);
    if (!ExitMI)
      continue;

    // An exit that is in scope is one the sequence can be placed at, so it has
    // a position by construction. Emitting at the end of the block instead
    // would put the sequence after the instruction control leaves through.
    //
    // If that construction ever fails, the compilation fails with it. Carrying
    // on past an exit the sequence could not be placed at produces the one
    // output the attribute exists to rule out: a function that reports itself
    // protected and leaves through a point at which nothing was cleared, with
    // nothing said about it. There is no way to reach this from IR today; it
    // is here so that a later change which introduces one is stopped rather
    // than absorbed.
    MachineBasicBlock::iterator InsertPt = getClearingInsertPoint(MBB, *ExitMI);
    if (InsertPt == MBB.end()) {
      if (Plan.anyStepEmits())
        MF.getFunction().getContext().diagnose(DiagnosticInfoUnsupported{
            MF.getFunction(),
            "clearing sequence could not be placed at an exit of this "
            "function"});
      continue;
    }

    if (PrintClearingSequence)
      OS << "  " << printMBBReference(MBB) << " "
         << getExitKindName(*ExitMI) << ":";

    // What the steps in front of the register clear leave in registers. It is
    // built as the sequence runs at this exit and read by the register clear
    // at this exit; see the comment on scratch registers above.
    BitVector ScratchRegs(TRI.getNumRegs());

    // What the sequence cleared here, collected as it runs and used once it
    // has finished; see the comment on keeping the clears above.
    BitVector ClearedRegs(TRI.getNumRegs());

    for (ClearingStep Step : ClearingSequence) {
      ClearingDisposition D = Plan.dispositionOf(Step);
      if (D == ClearingDisposition::Emit)
        emitClearingStep(Step, Plan, MBB, InsertPt, ScratchRegs, ClearedRegs);
      if (PrintClearingSequence)
        OS << " " << getClearingStepName(Step) << "="
           << getClearingDispositionName(D);
    }

    if (PrintClearingSequence) {
      // Only when there are any, so that the line a function without a step
      // that declares registers prints is the line it printed before.
      if (ScratchRegs.any()) {
        OS << " scratch=";
        const char *Sep = "";
        for (unsigned Reg : ScratchRegs.set_bits()) {
          OS << Sep << TRI.getName(Reg);
          Sep = ",";
        }
      }
      OS << "\n";
    }

    // Strictly after the sequence has run, and so strictly after the register
    // clear has decided what it covers here. The registers this adds to the
    // exit are registers the exit reads, and computeRegsToClearAtExit spares
    // every register the exit reads: add them first and the register clear
    // spares exactly the registers it was about to clear, and spares them
    // silently, the result being a function that reports itself protected and
    // clears nothing.
    anchorClearedRegsAtExit(MBB, *ExitMI, ClearedRegs, TFI);
  }

  if (PrintClearingSequence)
    OS << "end clearing sequence for function '" << MF.getName() << "'\n";
}

/// emitClearingStep - Emit one step of the clearing sequence at \p InsertPt.
///
/// \p ScratchRegs carries the registers the steps already run at this exit
/// used, and so left holding what they destroyed. A step adds the registers it
/// used to it, and the register clear reads it; see the comment on scratch
/// registers above.
///
/// \p ClearedRegs collects the registers the sequence has cleared here, for
/// the implicit uses that keep the clears; see the comment on keeping the
/// clears above.
///
/// A step that emits nothing today still has its case here, so that the
/// implementation of it lands at the position the order gives it rather than
/// wherever it is convenient.
void PEIImpl::emitClearingStep(ClearingStep Step, const ExitClearingPlan &Plan,
                               MachineBasicBlock &MBB,
                               MachineBasicBlock::iterator InsertPt,
                               BitVector &ScratchRegs, BitVector &ClearedRegs) {
  MachineFunction &MF = *MBB.getParent();
  const TargetFrameLowering &TFI = *MF.getSubtarget().getFrameLowering();
  const TargetRegisterInfo &TRI = *MF.getSubtarget().getRegisterInfo();

  switch (Step) {
  case ClearingStep::ClearStack:
    // Nothing emits here yet: no target can clear the frame, so nothing is
    // used and nothing real is declared;
    // trailofbits/vspells-ct-internal-notes#26. The step is first in the order
    // because clearing the frame needs registers to run, and it declares them
    // here so that the register clear behind it destroys them.
    declareStackClearScratchRegs(TRI, ScratchRegs);
    break;

  case ClearingStep::ClearRegisters: {
    // What to clear is settled here rather than in the plan, because it is the
    // exit that decides it: see computeRegsToClearAtExit.
    BitVector RegsToZero =
        computeRegsToClearAtExit(Plan.CandidateRegsToZero, MBB, InsertPt, TRI);

    // On top of that, whatever the steps in front of this one declared. The
    // declarations are folded in after the exit has narrowed the candidates
    // and not before, because narrowing them away is exactly what would
    // happen: a declared register is one the sequence dirtied on the way here,
    // not one the function used, and the narrowing is there to spare what the
    // exit still needs.
    assert(!anyRegNeededAtExit(ScratchRegs, MBB, InsertPt, TRI) &&
           "a step of the clearing sequence declared as scratch a register "
           "whose value at the exit something depends on");
    RegsToZero |= ScratchRegs;

    // The registers to put on the exit are the ones the clear writes, which
    // are not the ones it was asked to clear: the request names every
    // allocatable alias of a register, and the target picks which of them to
    // write, so x86 is asked for %rax, %eax, %ax, %al and %ah and emits one
    // instruction defining %eax. Reading the emitted instructions back is what
    // gives the registers that exist. The range is what was inserted in front
    // of InsertPt just now.
    MachineBasicBlock::iterator Emitted = InsertPt;
    bool AtBegin = Emitted == MBB.begin();
    MachineBasicBlock::iterator Before;
    if (!AtBegin)
      Before = std::prev(Emitted);

    TFI.emitZeroCallUsedRegs(RegsToZero, MBB, InsertPt, RS);

    for (MachineInstr &MI :
         make_range(AtBegin ? MBB.begin() : std::next(Before), InsertPt))
      for (const MachineOperand &MO : MI.operands()) {
        if (!MO.isReg() || !MO.isDef() || !MO.getReg())
          continue;
        // Only what was asked for. A clear writes registers on the side that
        // are not part of what it destroys -- an XOR sets the flags -- and
        // saying the function leaves those behind would be saying something
        // else, and something untrue.
        for (MCPhysReg SReg : TRI.sub_and_superregs_inclusive(MO.getReg()))
          if (RegsToZero.test(SReg)) {
            ClearedRegs.set(MO.getReg().id());
            break;
          }
      }
    break;
  }

  case ClearingStep::ClearFlags:
    // Nothing emits here yet. It is last in the order because every step in
    // front of it writes the flags, so a flag clear anywhere else is undone by
    // what follows it.
    break;
  }
}

/// planClearingSequence - Decide what each step of the sequence does in \p MF.
///
/// The steps are planned in the order they run, so that a function asking for
/// more than one of them is told about them in that order too.
void PEIImpl::planClearingSequence(MachineFunction &MF,
                                   ExitClearingPlan &Plan) {
  Plan.Stack = planClearStack(MF);
  Plan.Registers = planClearRegisters(MF, Plan.CandidateRegsToZero);

  // A step that runs in front of the register clear leaves the registers it
  // worked through holding what it destroyed, and the register clear is what
  // destroys those in turn. So once such a step runs, the register clear runs
  // with it, whether or not the function asked for one: "zero-call-used-regs"
  // is how a function asks for its own registers to be cleared, and these are
  // not its registers, they are the sequence's. That includes a function that
  // asked for "skip", which declines a clear of what the function itself left
  // in registers and says nothing about what clearing its frame put there. A
  // function with no step in front of the register clear is untouched by this.
  if (Plan.Stack == ClearingDisposition::Emit &&
      Plan.Registers == ClearingDisposition::NotRequested)
    Plan.Registers =
        planClearRegistersForScratch(MF, Plan.CandidateRegsToZero);

  // Nothing asks for the flags to be cleared and nothing clears them. The step
  // is planned all the same, so that the sequence a function runs is described
  // by the plan in full rather than in the parts that have an implementation.
  Plan.Flags = ClearingDisposition::Unimplemented;
}

/// planClearStack - Decide what the ClearStack step does in \p MF, reporting a
/// request the target cannot discharge.
ClearingDisposition PEIImpl::planClearStack(MachineFunction &MF) {
  const Function &F = MF.getFunction();

  if (!F.hasZeroizeStack())
    return ClearingDisposition::NotRequested;

  // The stand-in for the implementation of this step answers the capability
  // question instead of asking it, because what it stands in for is a target
  // that has the capability. It emits nothing; what it does is declare the
  // registers such a step would have used, so that what the rest of the
  // sequence does with them can be exercised.
  if (!StandInStackScratchRegs.empty())
    return ClearingDisposition::Emit;

  const TargetFrameLowering &TFI = *MF.getSubtarget().getFrameLowering();
  if (!TFI.supportsZeroizeStack(MF)) {
    F.getContext().diagnose(DiagnosticInfoUnsupported{
        F, "\"zeroize-stack\" is not supported by this target",
        DiagnosticLocation(), DS_Warning});
    return ClearingDisposition::Unsupported;
  }

  // No target implements the step yet, so a supported request reports
  // unimplemented rather than silently emitting nothing.
  return ClearingDisposition::Unimplemented;
}

/// planClearRegistersForScratch - Turn the ClearRegisters step on in a
/// function that did not ask for it, because a step in front of it does run
/// and will leave registers holding what it destroyed.
///
/// The candidate set is left empty on purpose: nothing about the function
/// selects a register here, and what is cleared at each exit is exactly what
/// the steps in front of the register clear declare at that exit.
ClearingDisposition
PEIImpl::planClearRegistersForScratch(MachineFunction &MF,
                                      BitVector &CandidateRegsToZero) {
  const Function &F = MF.getFunction();
  const TargetFrameLowering &TFI = *MF.getSubtarget().getFrameLowering();
  const TargetRegisterInfo &TRI = *MF.getSubtarget().getRegisterInfo();

  // A target that cannot clear registers cannot finish clearing the frame
  // either: the sequence would end with the frame's contents in the registers
  // it read them through, which is the disclosure the request was made to
  // prevent. Report it rather than emitting the half that works.
  if (!TFI.supportsZeroCallUsedRegs(MF)) {
    F.getContext().diagnose(DiagnosticInfoUnsupported{
        F, "clearing the stack needs the registers it uses to be cleared "
           "afterwards, which is not supported by this target"});
    return ClearingDisposition::Unsupported;
  }

  CandidateRegsToZero.resize(TRI.getNumRegs());
  return ClearingDisposition::Emit;
}

/// planClearRegisters - Decide what the ClearRegisters step does in \p MF, and
/// compute the registers it is allowed to clear.
///
/// What comes out is the candidate set, not the set cleared at any exit.
/// Whether a register can be cleared turns on two things: whether the mode
/// selects it (a question about the function, answered here) and whether it is
/// dead where the sequence runs (a question about one exit, answered by
/// computeRegsToClearAtExit).
ClearingDisposition
PEIImpl::planClearRegisters(MachineFunction &MF,
                            BitVector &CandidateRegsToZero) {
  const Function &F = MF.getFunction();

  if (!F.hasFnAttribute("zero-call-used-regs"))
    return ClearingDisposition::NotRequested;

  using namespace ZeroCallUsedRegs;

  ZeroCallUsedRegsKind ZeroRegsKind = getZeroCallUsedRegsKind(F);
  if (ZeroRegsKind == ZeroCallUsedRegsKind::Skip)
    return ClearingDisposition::NotRequested;

  // Ask the target whether it can discharge the request before computing what
  // to clear. A target that cannot has to say so: emitZeroCallUsedRegs does
  // nothing by default, so going ahead would leave the registers holding the
  // values the attribute exists to destroy, with nothing to tell the caller
  // that they still do.
  const TargetFrameLowering &TFI = *MF.getSubtarget().getFrameLowering();
  if (!TFI.supportsZeroCallUsedRegs(MF)) {
    F.getContext().diagnose(DiagnosticInfoUnsupported{
        F, "\"zero-call-used-regs\" is not supported by this target"});
    return ClearingDisposition::Unsupported;
  }

  const bool OnlyGPR = static_cast<unsigned>(ZeroRegsKind) & ONLY_GPR;
  const bool OnlyUsed = static_cast<unsigned>(ZeroRegsKind) & ONLY_USED;
  const bool OnlyArg = static_cast<unsigned>(ZeroRegsKind) & ONLY_ARG;

  const TargetRegisterInfo &TRI = *MF.getSubtarget().getRegisterInfo();
  const BitVector AllocatableSet(TRI.getAllocatableSet(MF));

  // Mark all used registers.
  //
  // Every register operand counts, whether the instruction names it or carries
  // it implicitly. An implicit operand is how the machine layer writes down a
  // register an instruction touches without being told to, which is exactly
  // the case where a narrowing this set drives cannot be justified: the
  // register was written, the value is there, and the mode's promise is that
  // what the function touched does not outlive it.
  //
  // Inline assembly is the case that made this visible. Every register an asm
  // block names -- its clobber list and its physical-register outputs alike --
  // reaches the machine layer as an implicit operand of the INLINEASM
  // instruction, so skipping implicit operands made an asm block invisible
  // here. A function whose only register traffic was an asm block cleared
  // nothing at all under a "used" mode, and the asm's registers carried their
  // contents past the return. Opaque target operations behave the same way for
  // the same reason: a division's remainder register, a return value that no
  // longer has a copy naming it, anything a pseudo defines on the side.
  BitVector UsedRegs(TRI.getNumRegs());
  if (OnlyUsed)
    for (const MachineBasicBlock &MBB : MF)
      for (const MachineInstr &MI : MBB) {
        // skip debug instructions
        if (MI.isDebugInstr())
          continue;

        for (const MachineOperand &MO : MI.operands()) {
          if (!MO.isReg())
            continue;

          MCRegister Reg = MO.getReg();
          if (AllocatableSet[Reg.id()] && (MO.isDef() || MO.isUse()))
            UsedRegs.set(Reg.id());
        }
      }

  // Get a list of registers that are used.
  BitVector LiveIns(TRI.getNumRegs());
  for (const MachineBasicBlock::RegisterMaskPair &LI : MF.front().liveins())
    LiveIns.set(LI.PhysReg);

  CandidateRegsToZero.resize(TRI.getNumRegs());
  for (MCRegister Reg : AllocatableSet.set_bits()) {
    // Skip over fixed registers.
    if (TRI.isFixedRegister(MF, Reg))
      continue;

    // Want only general purpose registers.
    if (OnlyGPR && !TRI.isGeneralPurposeRegister(MF, Reg))
      continue;

    // Want only used registers.
    if (OnlyUsed && !UsedRegs[Reg.id()])
      continue;

    // Want only registers used for arguments.
    if (OnlyArg) {
      if (OnlyUsed) {
        for (MCRegister LiveReg : LiveIns.set_bits()) {
          if (TRI.regsOverlap(Reg, LiveReg))
            CandidateRegsToZero.set(LiveReg);
        }
        continue;
      } else if (!TRI.isArgumentRegister(MF, Reg)) {
        continue;
      }
    }

    CandidateRegsToZero.set(Reg.id());
  }

  // Registers still needed where the sequence runs are taken out per exit, not
  // here: doing it here means the union over the exits, which leaves a register
  // one exit needs holding a value at every other one.

  // Callee-saved registers are the function's to preserve, though: one has to
  // hold what the caller left in it wherever the function leaves, so no exit
  // can clear it.
  for (const MCPhysReg *CSRegs = TRI.getCalleeSavedRegs(&MF);
       MCPhysReg CSReg = *CSRegs; ++CSRegs)
    for (MCRegister Reg : TRI.sub_and_superregs_inclusive(CSReg))
      CandidateRegsToZero.reset(Reg.id());

  return ClearingDisposition::Emit;
}

/// Report a clearing request dropped because the function is naked. PEI lays
/// out no frame and writes no epilogue for one, so "zeroize-stack" has nothing
/// to clear and "zero-call-used-regs", emitted into the epilogue, has nowhere
/// to go. Neither can be honored on any target, so the message names the
/// attribute rather than the target and stays true once one implements
/// clearing. Warnings, not errors: a request that cannot be met is no reason to
/// refuse to compile.
void PEIImpl::diagnoseIgnoredZeroizeRequestsOnNakedFunction(
    MachineFunction &MF) {
  const Function &F = MF.getFunction();

  if (!F.hasFnAttribute(Attribute::Naked))
    return;

  if (F.hasZeroizeStack())
    F.getContext().diagnose(DiagnosticInfoUnsupported{
        F,
        "\"zeroize-stack\" ignored on a \"naked\" function: no frame is "
        "generated to clear",
        DiagnosticLocation(), DS_Warning});

  using namespace ZeroCallUsedRegs;

  // "skip" asks for no clearing, so nothing is ignored. It must stay silent:
  // the attribute is often set to "skip" wholesale, which would otherwise make
  // naked functions unwritable in a translation unit that opts out.
  if (getZeroCallUsedRegsKind(F) != ZeroCallUsedRegsKind::Skip)
    F.getContext().diagnose(DiagnosticInfoUnsupported{
        F,
        "\"zero-call-used-regs\" ignored on a \"naked\" function: no epilogue "
        "is generated to clear in",
        DiagnosticLocation(), DS_Warning});
}

/// Replace all FrameIndex operands with physical register references and actual
/// offsets.
void PEIImpl::replaceFrameIndicesBackward(MachineFunction &MF) {
  const TargetFrameLowering &TFI = *MF.getSubtarget().getFrameLowering();

  for (auto &MBB : MF) {
    int SPAdj = 0;
    if (!MBB.succ_empty()) {
      // Get the SP adjustment for the end of MBB from the start of any of its
      // successors. They should all be the same.
      assert(all_of(MBB.successors(), [&MBB](const MachineBasicBlock *Succ) {
        return Succ->getCallFrameSize() ==
               (*MBB.succ_begin())->getCallFrameSize();
      }));
      const MachineBasicBlock &FirstSucc = **MBB.succ_begin();
      SPAdj = TFI.alignSPAdjust(FirstSucc.getCallFrameSize());
      if (TFI.getStackGrowthDirection() == TargetFrameLowering::StackGrowsUp)
        SPAdj = -SPAdj;
    }

    replaceFrameIndicesBackward(&MBB, MF, SPAdj);

    // We can't track the call frame size after call frame pseudos have been
    // eliminated. Set it to zero everywhere to keep MachineVerifier happy.
    MBB.setCallFrameSize(0);
  }
}

/// replaceFrameIndices - Replace all MO_FrameIndex operands with physical
/// register references and actual offsets.
void PEIImpl::replaceFrameIndices(MachineFunction &MF) {
  const TargetFrameLowering &TFI = *MF.getSubtarget().getFrameLowering();

  for (auto &MBB : MF) {
    int SPAdj = TFI.alignSPAdjust(MBB.getCallFrameSize());
    if (TFI.getStackGrowthDirection() == TargetFrameLowering::StackGrowsUp)
      SPAdj = -SPAdj;

    replaceFrameIndices(&MBB, MF, SPAdj);

    // We can't track the call frame size after call frame pseudos have been
    // eliminated. Set it to zero everywhere to keep MachineVerifier happy.
    MBB.setCallFrameSize(0);
  }
}

bool PEIImpl::replaceFrameIndexDebugInstr(MachineFunction &MF, MachineInstr &MI,
                                          unsigned OpIdx, int SPAdj) {
  const TargetFrameLowering *TFI = MF.getSubtarget().getFrameLowering();
  const TargetRegisterInfo &TRI = *MF.getSubtarget().getRegisterInfo();
  if (MI.isDebugValue()) {

    MachineOperand &Op = MI.getOperand(OpIdx);
    assert(MI.isDebugOperand(&Op) &&
           "Frame indices can only appear as a debug operand in a DBG_VALUE*"
           " machine instruction");
    Register Reg;
    unsigned FrameIdx = Op.getIndex();
    unsigned Size = MF.getFrameInfo().getObjectSize(FrameIdx);

    StackOffset Offset = TFI->getFrameIndexReference(MF, FrameIdx, Reg);
    Op.ChangeToRegister(Reg, false /*isDef*/);

    const DIExpression *DIExpr = MI.getDebugExpression();

    // If we have a direct DBG_VALUE, and its location expression isn't
    // currently complex, then adding an offset will morph it into a
    // complex location that is interpreted as being a memory address.
    // This changes a pointer-valued variable to dereference that pointer,
    // which is incorrect. Fix by adding DW_OP_stack_value.

    if (MI.isNonListDebugValue()) {
      unsigned PrependFlags = DIExpression::ApplyOffset;
      if (!MI.isIndirectDebugValue() && !DIExpr->isComplex())
        PrependFlags |= DIExpression::StackValue;

      // If we have DBG_VALUE that is indirect and has a Implicit location
      // expression need to insert a deref before prepending a Memory
      // location expression. Also after doing this we change the DBG_VALUE
      // to be direct.
      if (MI.isIndirectDebugValue() && DIExpr->isImplicit()) {
        SmallVector<uint64_t, 2> Ops = {dwarf::DW_OP_deref_size, Size};
        bool WithStackValue = true;
        DIExpr = DIExpression::prependOpcodes(DIExpr, Ops, WithStackValue);
        // Make the DBG_VALUE direct.
        MI.getDebugOffset().ChangeToRegister(0, false);
      }
      DIExpr = TRI.prependOffsetExpression(DIExpr, PrependFlags, Offset);
    } else {
      // The debug operand at DebugOpIndex was a frame index at offset
      // `Offset`; now the operand has been replaced with the frame
      // register, we must add Offset with `register x, plus Offset`.
      unsigned DebugOpIndex = MI.getDebugOperandIndex(&Op);
      SmallVector<uint64_t, 3> Ops;
      TRI.getOffsetOpcodes(Offset, Ops);
      DIExpr = DIExpression::appendOpsToArg(DIExpr, Ops, DebugOpIndex);
    }
    MI.getDebugExpressionOp().setMetadata(DIExpr);
    return true;
  }

  if (MI.isDebugPHI()) {
    // Allow stack ref to continue onwards.
    return true;
  }

  // TODO: This code should be commoned with the code for
  // PATCHPOINT. There's no good reason for the difference in
  // implementation other than historical accident.  The only
  // remaining difference is the unconditional use of the stack
  // pointer as the base register.
  if (MI.getOpcode() == TargetOpcode::STATEPOINT) {
    assert((!MI.isDebugValue() || OpIdx == 0) &&
           "Frame indices can only appear as the first operand of a "
           "DBG_VALUE machine instruction");
    Register Reg;
    MachineOperand &Offset = MI.getOperand(OpIdx + 1);
    StackOffset refOffset = TFI->getFrameIndexReferencePreferSP(
        MF, MI.getOperand(OpIdx).getIndex(), Reg, /*IgnoreSPUpdates*/ false);
    assert(!refOffset.getScalable() &&
           "Frame offsets with a scalable component are not supported");
    Offset.setImm(Offset.getImm() + refOffset.getFixed() + SPAdj);
    MI.getOperand(OpIdx).ChangeToRegister(Reg, false /*isDef*/);
    return true;
  }
  return false;
}

void PEIImpl::replaceFrameIndicesBackward(MachineBasicBlock *BB,
                                          MachineFunction &MF, int &SPAdj) {
  assert(MF.getSubtarget().getRegisterInfo() &&
         "getRegisterInfo() must be implemented!");

  const TargetInstrInfo &TII = *MF.getSubtarget().getInstrInfo();
  const TargetRegisterInfo &TRI = *MF.getSubtarget().getRegisterInfo();
  const TargetFrameLowering &TFI = *MF.getSubtarget().getFrameLowering();

  RegScavenger *LocalRS = FrameIndexEliminationScavenging ? RS : nullptr;
  if (LocalRS)
    LocalRS->enterBasicBlockEnd(*BB);

  for (MachineBasicBlock::iterator I = BB->end(); I != BB->begin();) {
    MachineInstr &MI = *std::prev(I);

    if (TII.isFrameInstr(MI)) {
      SPAdj -= TII.getSPAdjust(MI);
      TFI.eliminateCallFramePseudoInstr(MF, *BB, &MI);
      continue;
    }

    // Step backwards to get the liveness state at (immedately after) MI.
    if (LocalRS)
      LocalRS->backward(I);

    bool RemovedMI = false;
    for (const auto &[Idx, Op] : enumerate(MI.operands())) {
      if (!Op.isFI())
        continue;

      if (replaceFrameIndexDebugInstr(MF, MI, Idx, SPAdj))
        continue;

      // Eliminate this FrameIndex operand.
      RemovedMI = TRI.eliminateFrameIndex(MI, SPAdj, Idx, LocalRS);
      if (RemovedMI)
        break;
    }

    if (!RemovedMI)
      --I;
  }
}

void PEIImpl::replaceFrameIndices(MachineBasicBlock *BB, MachineFunction &MF,
                                  int &SPAdj) {
  assert(MF.getSubtarget().getRegisterInfo() &&
         "getRegisterInfo() must be implemented!");
  const TargetInstrInfo &TII = *MF.getSubtarget().getInstrInfo();
  const TargetRegisterInfo &TRI = *MF.getSubtarget().getRegisterInfo();
  const TargetFrameLowering *TFI = MF.getSubtarget().getFrameLowering();

  bool InsideCallSequence = false;

  for (MachineBasicBlock::iterator I = BB->begin(); I != BB->end(); ) {
    if (TII.isFrameInstr(*I)) {
      InsideCallSequence = TII.isFrameSetup(*I);
      SPAdj += TII.getSPAdjust(*I);
      I = TFI->eliminateCallFramePseudoInstr(MF, *BB, I);
      continue;
    }

    MachineInstr &MI = *I;
    bool DoIncr = true;
    bool DidFinishLoop = true;
    for (unsigned i = 0, e = MI.getNumOperands(); i != e; ++i) {
      if (!MI.getOperand(i).isFI())
        continue;

      if (replaceFrameIndexDebugInstr(MF, MI, i, SPAdj))
        continue;

      // Some instructions (e.g. inline asm instructions) can have
      // multiple frame indices and/or cause eliminateFrameIndex
      // to insert more than one instruction. We need the register
      // scavenger to go through all of these instructions so that
      // it can update its register information. We keep the
      // iterator at the point before insertion so that we can
      // revisit them in full.
      bool AtBeginning = (I == BB->begin());
      if (!AtBeginning) --I;

      // If this instruction has a FrameIndex operand, we need to
      // use that target machine register info object to eliminate
      // it.
      TRI.eliminateFrameIndex(MI, SPAdj, i, RS);

      // Reset the iterator if we were at the beginning of the BB.
      if (AtBeginning) {
        I = BB->begin();
        DoIncr = false;
      }

      DidFinishLoop = false;
      break;
    }

    // If we are looking at a call sequence, we need to keep track of
    // the SP adjustment made by each instruction in the sequence.
    // This includes both the frame setup/destroy pseudos (handled above),
    // as well as other instructions that have side effects w.r.t the SP.
    // Note that this must come after eliminateFrameIndex, because
    // if I itself referred to a frame index, we shouldn't count its own
    // adjustment.
    if (DidFinishLoop && InsideCallSequence)
      SPAdj += TII.getSPAdjust(MI);

    if (DoIncr && I != BB->end())
      ++I;
  }
}
