// RUN: %clang_cc1 -triple x86_64-unknown-linux-gnu -fno-rtti -emit-llvm \
// RUN:   %s -o - | FileCheck %s --check-prefixes=CHECK,DEFAULT
// RUN: %clang_cc1 -triple x86_64-unknown-linux-gnu -fno-rtti -emit-llvm \
// RUN:   -fzero-call-used-regs=used-gpr %s -o - | FileCheck %s --check-prefixes=CHECK,REGS

struct D { virtual int g(int); int d; };
struct E { virtual int g(int); int e; };
struct F : D, E { [[clang::zeroize_on_return]] int g(int) override; };

// CHECK-LABEL: define {{.*}} @_ZN1F1gEi(
// CHECK-SAME: #[[PROTECTED:[0-9]+]]
int F::g(int x) { return x; }

// Ordinary forwarding thunks also leave the method's requests on the callee.
// CHECK-LABEL: define {{.*}} @_ZThn16_N1F1gEi(
// CHECK-SAME: #[[FORWARD:[0-9]+]]
// CHECK: call {{.*}}i32 @_ZN1F1gEi(
// CHECK: ret i32

// CHECK: attributes #[[PROTECTED]] = {
// CHECK-SAME: "zero-call-used-regs"="all" "zeroize-stack"="used"
// CHECK: attributes #[[FORWARD]] = {
// DEFAULT-NOT: "zero-call-used-regs"
// REGS-SAME: "zero-call-used-regs"="used-gpr"
// CHECK-NOT: "zeroize-stack"
// CHECK-SAME: }
