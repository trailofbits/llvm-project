//===- AArch64Zeroization.h - Final AArch64 zeroization checks --*- C++ -*-===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#ifndef LLVM_LIB_TARGET_AARCH64_AARCH64ZEROIZATION_H
#define LLVM_LIB_TARGET_AARCH64_AARCH64ZEROIZATION_H

namespace llvm {
class BitVector;
class MachineFunction;
class MachineInstr;

/// Whether the fixed-width ordinary ELF register contract can be checked.
bool shouldVerifyAArch64ZeroizedRegisters(const MachineFunction &MF);

/// Freeze the per-exit target requirements before emitting or retaining clears.
void recordAArch64ZeroizationObligation(MachineInstr &Exit,
                                        const BitVector &FullRegs);

/// Diagnose a required register or NZCV value not proven zero at a final
/// return.
bool verifyAArch64Zeroization(const MachineFunction &MF);
} // namespace llvm

#endif
