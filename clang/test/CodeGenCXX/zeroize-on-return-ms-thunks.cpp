// RUN: %clang_cc1 -triple i686-pc-windows-msvc -fno-rtti -emit-llvm \
// RUN:   %s -o - | FileCheck %s --check-prefixes=CHECK,DEFAULT
// RUN: %clang_cc1 -triple i686-pc-windows-msvc -fno-rtti -emit-llvm \
// RUN:   -fzero-call-used-regs=used-gpr %s -o - | FileCheck %s --check-prefixes=CHECK,REGS

struct NonTrivial {
  NonTrivial(const NonTrivial &);
  ~NonTrivial();
  int value;
};
struct A { virtual void f(NonTrivial); };
struct B { virtual void f(NonTrivial); };
struct C : A, B {
  [[clang::zeroize_on_return]] void f(NonTrivial) override;
};

// CHECK-LABEL: define {{.*}} @"?f@C@@UAEXUNonTrivial@@@Z"(
// CHECK-SAME: #[[PROTECTED:[0-9]+]]
void C::f(NonTrivial) { [[clang::sensitive]] volatile int key = 42; }

// CHECK-LABEL: define {{.*}} @"?f@C@@W3AEXUNonTrivial@@@Z"(
// CHECK-SAME: inalloca
// CHECK-SAME: #[[FORWARD:[0-9]+]]
// CHECK: musttail call x86_thiscallcc void @"?f@C@@UAEXUNonTrivial@@@Z"(
// CHECK-NEXT: ret void

// CHECK: attributes #[[PROTECTED]] = {
// CHECK-SAME: "zero-call-used-regs"="all" "zeroize-stack"="used"
// CHECK: attributes #[[FORWARD]] = {
// DEFAULT-NOT: "zero-call-used-regs"
// REGS-SAME: "zero-call-used-regs"="used-gpr"
// CHECK-NOT: "zeroize-stack"
// CHECK-SAME: }
