// REQUIRES: arm-registered-target
// RUN: %clang_cc1 -triple armv7-none-eabi -std=c23 -S -O0 -mllvm -verify-machineinstrs %s -o - \
// RUN:   | FileCheck %s --check-prefixes=CHECK,ARM --implicit-check-not='{{mov(s|w|\.w)?}} r0, #0'
// RUN: %clang_cc1 -triple armv7-none-eabi -std=c23 -S -O2 -mllvm -verify-machineinstrs %s -o - \
// RUN:   | FileCheck %s --check-prefixes=CHECK,ARM --implicit-check-not='{{mov(s|w|\.w)?}} r0, #0'
// RUN: %clang_cc1 -triple thumbv7-none-eabi -std=c23 -S -O2 -mllvm -verify-machineinstrs %s -o - \
// RUN:   | FileCheck %s --check-prefixes=CHECK,ARM --implicit-check-not='{{mov(s|w|\.w)?}} r0, #0'
// RUN: %clang_cc1 -triple thumbv6m-none-eabi -std=c23 -S -O0 -mllvm -verify-machineinstrs %s -o - \
// RUN:   | FileCheck %s --check-prefixes=CHECK,M --implicit-check-not='{{mov(s|w|\.w)?}} r0, #0'
// RUN: %clang_cc1 -triple thumbv6m-none-eabi -std=c23 -S -O2 -mllvm -verify-machineinstrs %s -o - \
// RUN:   | FileCheck %s --check-prefixes=CHECK,M --implicit-check-not='{{mov(s|w|\.w)?}} r0, #0'

// The source annotation requests all three clearing steps. The owned slot is
// overwritten, the return value in r0 is preserved, and flags are cleared last.
// CHECK-LABEL: preserved:
// CHECK: mov{{(s|w|\.w)?}} [[ZERO:r[1-3]]], #0
// CHECK: str [[ZERO]], [
// CHECK: mov{{(s|w|\.w)?}} [[FLAGS:r[1-3]]], #0
// ARM: uadd8 [[FLAGS]], [[FLAGS]], [[FLAGS]]
// ARM-NEXT: msr APSR_nzcvq, [[FLAGS]]
// M: msr apsr{{(_nzcvq)?}}, [[FLAGS]]
// CHECK-NEXT: bx lr
[[clang::zeroize_on_return]] int preserved(int input) {
  volatile unsigned value = 42;
  return input;
}
