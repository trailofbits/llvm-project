// RUN: %clang_cc1 -triple x86_64-unknown-linux-gnu -fno-rtti -emit-llvm \
// RUN:   %s -o - | FileCheck %s

struct A { virtual A *clone(int, ...); int a; };
struct B { virtual B *clone(int, ...); int b; };
struct C : A, B {
  [[clang::zeroize_on_return]] C *clone(int, ...) override;
};

// CHECK-LABEL: define {{.*}} @_ZN1C5cloneEiz(
// CHECK-SAME: #[[PROTECTED:[0-9]+]]
// CHECK: %key = alloca i32
C *C::clone(int, ...) {
  [[clang::sensitive]] volatile int key = 42;
  return this;
}

// Return adjustment prevents musttail forwarding; this thunk clones the body.
// CHECK-LABEL: define {{.*}} @_ZTchn16_h16_N1C5cloneEiz(
// CHECK-SAME: #[[PROTECTED]]
// CHECK: %key = alloca i32
// CHECK-NOT: musttail
// CHECK: ret ptr

// CHECK: attributes #[[PROTECTED]] = {
// CHECK-SAME: "zero-call-used-regs"="all" "zeroize-stack"="used"
