// REQUIRES: aarch64-registered-target
// RUN: %clang_cc1 -triple aarch64-unknown-linux-gnu -std=c23 -S -O0 \
// RUN:   -mllvm -verify-machineinstrs %s -o - | FileCheck %s \
// RUN:   --implicit-check-not='mov {{[xw]}}0, {{(xzr|wzr|#0)}}'
// RUN: %clang_cc1 -triple aarch64-unknown-linux-gnu -std=c23 -S -O2 \
// RUN:   -mllvm -verify-machineinstrs %s -o - | FileCheck %s \
// RUN:   --implicit-check-not='mov {{[xw]}}0, {{(xzr|wzr|#0)}}'

// Clearing covers the owned slot, preserves the return value in x0, and leaves
// NZCV clearing after stack release and register clearing.
// CHECK-LABEL: preserved:
// CHECK: stp xzr, xzr,
// CHECK: mov sp,
// CHECK: mov x9, {{(xzr|#0)}}
// CHECK: msr NZCV, xzr
// CHECK-NEXT: ret
[[clang::zeroize_on_return]] unsigned long preserved(unsigned long input) {
  volatile unsigned long value = 42;
  return input;
}
