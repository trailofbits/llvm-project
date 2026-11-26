//===- RegisterClearing.h --------------------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#ifndef LLVM_LIB_CODEGEN_REGISTERCLEARING_H
#define LLVM_LIB_CODEGEN_REGISTERCLEARING_H

#include "llvm/ADT/BitVector.h"
#include "llvm/CodeGen/MachineBasicBlock.h"
#include "llvm/Support/Compiler.h"

namespace llvm {
class RegScavenger;

/// Retain the complete physical registers in \p Regs through the remaining
/// clearing steps. Preserve genuine operands of \p ExitMI and honor the
/// target's separate FAKE_USE policy, moving \p InsertPt before that use.
/// Unlike register-clear discovery, this includes explicit flags requirements.
/// The insertion point must precede or refer to \p ExitMI in the same block.
LLVM_ABI void retainClearingState(const BitVector &Regs,
                                  MachineBasicBlock::iterator &InsertPt,
                                  MachineInstr &ExitMI);

/// Validate \p ScratchRegs, merge them into \p RegsToZero, and emit at
/// \p InsertPt. Keep all emitted allocatable physical defs live through
/// clearing, including target scratch. Scratch declarations are per exit,
/// regardless of clearing mode. The caller must check
/// supportsZeroCallUsedRegs(). If the target requests a FAKE_USE, move \p
/// InsertPt before it so later clearing steps remain covered by its uses.
/// Diagnose invalid scratch and return false without emitting a clear.
LLVM_ABI bool emitZeroCallUsedRegsWithScratch(
    BitVector RegsToZero, const BitVector &ScratchRegs, MachineBasicBlock &MBB,
    MachineBasicBlock::iterator &InsertPt, MachineInstr &ExitMI,
    RegScavenger *RS);

} // namespace llvm

#endif
