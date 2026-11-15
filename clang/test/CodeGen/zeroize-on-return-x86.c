// REQUIRES: x86-registered-target
// RUN: %clang_cc1 -triple x86_64-unknown-linux-gnu -target-feature +sahf \
// RUN:   -std=c23 -S -O0 -mllvm -verify-machineinstrs %s -o - \
// RUN:   | FileCheck %s --implicit-check-not='xorl %eax, %eax'
// RUN: %clang_cc1 -triple x86_64-unknown-linux-gnu -target-feature +sahf \
// RUN:   -std=c23 -S -O2 -mllvm -verify-machineinstrs %s -o - \
// RUN:   | FileCheck %s --implicit-check-not='xorl %eax, %eax'

// The source annotation clears the owned frame and call-used registers, then
// clears arithmetic flags without writing the stack or losing the return value.
// CHECK-LABEL: preserved:
// CHECK: movl {{.*}}, %eax
// CHECK: mov{{[ql]}} $0, {{-?[0-9]+}}(%rsp)
// CHECK: xorl %r11d, %r11d
// CHECK: xchgq %r11, %rax
// CHECK-NEXT: testl %eax, %eax
// CHECK-NEXT: sahf
// CHECK-NEXT: xchgq %r11, %rax
// CHECK-NEXT: retq
[[clang::zeroize_on_return]] int preserved(int input) {
  volatile unsigned value = 42;
  return input;
}
