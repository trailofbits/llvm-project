//===-- ARMZeroizeCleanup.h - Fixed-frame EHABI clearing ---------*- C++
//-*-===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#ifndef LLVM_LIB_TARGET_ARM_ARMZEROIZECLEANUP_H
#define LLVM_LIB_TARGET_ARM_ARMZEROIZECLEANUP_H

#include "llvm/ADT/StringRef.h"

namespace llvm {
class MachineFunction;
class MachineInstr;
class MCSymbol;

bool isARMZeroizeCleanup(const MachineInstr &MI);
bool hasARMZeroizeCleanup(const MachineFunction &MF);
bool hasARMZeroizeCleanupFrame(const MachineFunction &MF);
bool hasARMZeroizeCleanupInterface(const MachineInstr &MI);
MCSymbol *getARMZeroizeSymbol(const MachineFunction &MF, StringRef Kind);
} // namespace llvm

#endif
