// RUN: %clang_cc1 -triple x86_64-unknown-linux-gnu -emit-llvm %s -o - | FileCheck %s
// RUN: %clang_cc1 -triple x86_64-unknown-linux-gnu -emit-llvm \
// RUN:   -fzero-call-used-regs=all %s -o - | FileCheck %s

// The existing main exemption also removes an explicit register-only attribute.
__attribute__((zero_call_used_regs("all"))) int main(void) { return 0; }

// CHECK: define {{.*}} @main() #[[MAIN:[0-9]+]]
// CHECK: attributes #[[MAIN]] = {
// CHECK-NOT: "zero-call-used-regs"
// CHECK-NOT: "zeroize-stack"
// CHECK-SAME: }
