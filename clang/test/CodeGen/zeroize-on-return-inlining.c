// RUN: %clang_cc1 -triple x86_64-unknown-linux-gnu -O2 -emit-llvm %s -o - | FileCheck %s

__attribute__((zeroize_on_return, always_inline))
static int protected_callee(int x) { return x + 1; }

// An inlining request cannot move a protected frame into an unprotected caller.
// CHECK-LABEL: define {{.*}} @plain_caller(
// CHECK: call {{.*}}i32 @protected_callee(
int plain_caller(int x) { return protected_callee(x); }

// CHECK-LABEL: define internal {{.*}} @protected_callee(
// CHECK-SAME: #[[PROTECTED:[0-9]+]]
// CHECK: attributes #[[PROTECTED]] = {
// CHECK-SAME: "zero-call-used-regs"="all" "zeroize-stack"="used"
