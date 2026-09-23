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
