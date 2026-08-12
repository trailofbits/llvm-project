//===- llvm/CodeGen/MachineFunctionExits.h ----------------------*- C++ -*-===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
//
// Enumerate the points at which control leaves a machine function and give
// each one a kind, for use after register allocation and frame finalization.
//
// A function that has been asked to destroy its registers or its frame has to
// do it wherever control leaves, not only where it returns. Finding those
// places is separate from emitting anything at them: what an exit can be given
// depends on what it does with the frame, and several exit shapes leave no
// position at which the frame is both still addressable and about to be
// released. Classifying first keeps that judgement in one place instead of
// spreading it over every emission site.
//
//===----------------------------------------------------------------------===//

#ifndef LLVM_CODEGEN_MACHINEFUNCTIONEXITS_H
#define LLVM_CODEGEN_MACHINEFUNCTIONEXITS_H

#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/StringRef.h"
#include "llvm/Support/Compiler.h"
#include <optional>

namespace llvm {

class MachineBasicBlock;
class MachineFunction;
class MachineInstr;
class raw_ostream;

/// The shapes control can take when it leaves a machine function.
///
/// The kinds are distinguished by what the exit does with the frame and with
/// the registers, because that is what decides whether a clearing sequence can
/// be placed at it, and by nothing else. isEnforceableExit() answers that
/// question for a kind; the comment on each kind for which it answers false
/// records why that exit is out of scope.
enum class MachineExitKind {
  /// A return that is not a call. The epilogue runs immediately in front of
  /// it, so there is a position at which the frame is still addressable and
  /// the registers still hold what the function put in them.
  Return,

  /// A return that is also a call, i.e. a tail call. The frame has already
  /// been released and the outgoing arguments are live, so the position in
  /// front of the terminator is not one at which the frame can be cleared,
  /// even though the terminator is marked as a return and so is reached by a
  /// walk over return blocks.
  TailCall,

  /// A return out of an exception-handling scope: cleanupret or catchret in a
  /// funclet-based personality. The unwinder gives control back to code in
  /// this function and takes it away again here, with the funclet's frame
  /// still established.
  EHScopeReturn,

  /// A call to the routine that resumes unwinding once a cleanup has run:
  /// _Unwind_Resume, or __cxa_end_cleanup under the ARM EH ABI. This is what
  /// a landing pad that only cleans up ends in, and it is the last point in
  /// the function on that path.
  UnwindResume,

  /// A block control does not come back from, ending in something this
  /// classification cannot account for: inline assembly, or a target
  /// operation whose effect on control flow is not modelled.
  ///
  /// In scope, because being unable to say what an exit does is not the same
  /// as knowing it does nothing. An opaque instruction at the end of a block
  /// with no successors may transfer out of the function -- inline assembly
  /// can jump, issue a system call that does not return, or return into
  /// another frame -- and the compiler has no way to establish that it does
  /// not. Clearing in front of it costs a dead sequence when control really
  /// does stop there, and clearing nothing costs the frame when it does not,
  /// so the uncertainty is resolved towards clearing.
  Unknown,

  /// A call after which control does not come back to this function: a call to
  /// a noreturn callee such as abort or exit, a throw with no cleanup in this
  /// function to catch it, or longjmp reached as an ordinary call.
  ///
  /// Out of scope. The frame is abandoned rather than released: nothing in
  /// this function runs after the call, and the caller's context is restored
  /// by the unwinder or by the jump itself, so there is no point at which a
  /// clearing sequence would run and still be the last thing to touch the
  /// frame.
  NoReturnCall,

  /// A jump out of the function: a target's setjmp/longjmp pseudo, or an
  /// indirect branch in a block with no successors.
  ///
  /// Out of scope, for the same reason as NoReturnCall. The threat model does
  /// not cover frames that are abandoned rather than left.
  NonLocalJump,

  /// A terminal block control does not leave the function through: a trap, or
  /// a block with nothing in it that an unreachable was lowered to.
  ///
  /// Out of scope: there is no transfer out of the frame to protect. Unlike
  /// Unknown, this is a positive finding rather than the absence of one. A
  /// block with no instructions left in it has nothing that could transfer
  /// anywhere, and an instruction the target has marked as a trap raises a
  /// fault rather than transferring; anything else that a block with no
  /// successors ends in is Unknown.
  Unreachable,
};

/// One point at which control leaves a machine function.
struct MachineExit {
  /// The block the exit is in.
  const MachineBasicBlock *MBB = nullptr;

  /// The instruction control leaves through. Null only for an Unreachable
  /// exit whose block has no instructions left in it.
  const MachineInstr *MI = nullptr;

  MachineExitKind Kind = MachineExitKind::Unreachable;
};

/// Whether a clearing sequence can be enforced at an exit of kind \p K.
///
/// False means the exit is out of scope, not that it was overlooked: see the
/// comment on the kind for the reason.
LLVM_ABI bool isEnforceableExit(MachineExitKind K);

/// A short stable name for \p K, as printed by -pei-print-exits.
LLVM_ABI StringRef getMachineExitKindName(MachineExitKind K);

/// Classify the exit of \p MBB, if it has one.
///
/// Returns std::nullopt when control does not leave the function from \p MBB,
/// that is, when \p MBB has successors and no return-shaped terminator.
LLVM_ABI std::optional<MachineExit>
classifyMachineExit(const MachineBasicBlock &MBB);

/// Collect every exit of \p MF, in block order.
LLVM_ABI void collectMachineFunctionExits(const MachineFunction &MF,
                                          SmallVectorImpl<MachineExit> &Exits);

/// Print the exits of \p MF, one per line, with the kind and whether clearing
/// can be enforced there.
LLVM_ABI void printMachineFunctionExits(raw_ostream &OS,
                                        const MachineFunction &MF);

} // end namespace llvm

#endif // LLVM_CODEGEN_MACHINEFUNCTIONEXITS_H
