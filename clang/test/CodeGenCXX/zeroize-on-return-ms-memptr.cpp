// RUN: %clang_cc1 -triple x86_64-pc-windows-msvc -fno-rtti -emit-llvm \
// RUN:   %s -o - | FileCheck %s --check-prefixes=CHECK,DEFAULT
// RUN: %clang_cc1 -triple x86_64-pc-windows-msvc -fno-rtti -emit-llvm \
// RUN:   -fzero-call-used-regs=used-gpr %s -o - | FileCheck %s --check-prefixes=CHECK,REGS

struct C { [[clang::zeroize_on_return]] virtual int f(int); };

// CHECK-LABEL: define {{.*}} @"?f@C@@UEAAHH@Z"(
// CHECK-SAME: #[[PROTECTED:[0-9]+]]
int C::f(int x) { return x; }

int (C::*pick())(int) { return &C::f; }

// CHECK-LABEL: define {{.*}} @"??_9C@@$BA@AA"(
// CHECK-SAME: #[[FORWARD:[0-9]+]]
// CHECK: musttail call void {{.*}}%{{.*}}(
// CHECK-NEXT: ret void

// CHECK: attributes #[[PROTECTED]] = {
// CHECK-SAME: "zero-call-used-regs"="all" "zeroize-stack"="used"
// CHECK: attributes #[[FORWARD]] = {
// DEFAULT-NOT: "zero-call-used-regs"
// REGS-SAME: "zero-call-used-regs"="used-gpr"
// CHECK-NOT: "zeroize-stack"
// CHECK-SAME: }
