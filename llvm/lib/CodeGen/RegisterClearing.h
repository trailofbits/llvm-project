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

/// Add validated scratch declarations to the exit's filtered register set and
/// emit the clear. The caller must check supportsZeroCallUsedRegs first.
/// Scratch declarations are per exit and independent of the function's mode.
/// Return false and diagnose an invalid declaration without emitting a clear.
LLVM_ABI bool emitZeroCallUsedRegsWithScratch(
    BitVector RegsToZero, const BitVector &ScratchRegs, MachineBasicBlock &MBB,
    MachineBasicBlock::iterator InsertPt, RegScavenger *RS);

} // namespace llvm

#endif
