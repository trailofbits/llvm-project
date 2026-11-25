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
class LiveRegUnits;
class MachineFunction;
class MachineInstr;
class MachineOperand;
class MCSymbol;

/// Whether the fixed-width ELF register contract can be checked in this
/// function.
bool shouldVerifyAArch64ZeroizedRegisters(const MachineFunction &MF);

/// Whether the base ELF ABI exposes fixed-width V8–V15 upper halves.
bool hasAArch64ZeroizeUpperLaneABI(const MachineFunction &MF);

/// Whether this is the supported Android SCS transfer to _Unwind_Resume.
bool isAArch64ZeroizeShadowResume(const MachineInstr &MI);

/// Experimental fixed-frame ELF cleanup transfer using a local carrier thunk.
bool isAArch64ZeroizeCarrierResume(const MachineInstr &MI);

/// Whether PEI established the constant continuation and retained caller state.
bool hasAArch64ZeroizeCarrierInterface(const MachineInstr &MI);

/// One public-control continuation per protected function, shared by its exits.
MCSymbol *getAArch64ZeroizeContinuation(const MachineFunction &MF);

/// Whether this calls one of the recognized C++ unwind-transfer entry points.
bool isAArch64ZeroizeUnwindResume(const MachineInstr &MI);

/// Whether an operand is a backend verification record (never an MC operand).
bool isAArch64ZeroizationObligation(const MachineOperand &MO);

/// Freeze the per-exit target requirements before emitting or retaining clears.
void recordAArch64ZeroizationObligation(MachineInstr &Exit,
                                        const BitVector &FullRegs,
                                        const BitVector &Selected,
                                        const LiveRegUnits &Interface);

/// Diagnose a required register or NZCV value not proven zero at a final
/// return or supported outgoing resume call.
bool verifyAArch64Zeroization(const MachineFunction &MF);
} // namespace llvm

#endif
