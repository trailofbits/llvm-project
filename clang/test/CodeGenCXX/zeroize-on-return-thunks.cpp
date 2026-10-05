// RUN: %clang_cc1 -triple x86_64-unknown-linux-gnu -fno-rtti -emit-llvm \
// RUN:   %s -o - | FileCheck %s --check-prefixes=CHECK,DEFAULT
// RUN: %clang_cc1 -triple x86_64-unknown-linux-gnu -fno-rtti -emit-llvm \
// RUN:   -fzero-call-used-regs=used-gpr %s -o - | FileCheck %s --check-prefixes=CHECK,REGS

struct A { virtual void f(int, ...); int a; };
struct B { virtual void f(int, ...); int b; };
struct C : A, B { [[clang::zeroize_on_return]] void f(int, ...) override; };

// CHECK-LABEL: define {{.*}} @_ZN1C1fEiz(
// CHECK-SAME: #[[PROTECTED:[0-9]+]]
void C::f(int, ...) { [[clang::sensitive]] volatile int key = 42; }

// CHECK-LABEL: define {{.*}} @_ZThn16_N1C1fEiz(
// CHECK-SAME: #[[FORWARD:[0-9]+]]
// CHECK: musttail call void {{.*}}@_ZN1C1fEiz(
// CHECK-NEXT: ret void

// CHECK: attributes #[[PROTECTED]] = {
// CHECK-SAME: "zero-call-used-regs"="all" "zeroize-stack"="used"
// CHECK: attributes #[[FORWARD]] = {
// DEFAULT-NOT: "zero-call-used-regs"
// REGS-SAME: "zero-call-used-regs"="used-gpr"
// CHECK-NOT: "zeroize-stack"
// CHECK-SAME: }
