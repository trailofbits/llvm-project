//===- X86ZeroizeLVIReturn.h - Protected LVI returns ------------*- C++ -*-===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#ifndef LLVM_LIB_TARGET_X86_X86ZEROIZELVIRETURN_H
#define LLVM_LIB_TARGET_X86_X86ZEROIZELVIRETURN_H

namespace llvm {
class MachineFunction;

bool isX86ZeroizeLVIReturn(const MachineFunction &MF);
bool verifyX86ZeroizeLVIReturns(const MachineFunction &MF);
} // namespace llvm

#endif
