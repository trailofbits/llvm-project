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
class MachineFunction;

/// Diagnose an ordinary machine return without a reaching NZCV clear.
bool verifyAArch64ZeroizedFlags(const MachineFunction &MF);
} // namespace llvm

#endif
