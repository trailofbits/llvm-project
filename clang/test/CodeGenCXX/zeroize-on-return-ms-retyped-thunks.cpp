// RUN: %clang_cc1 -triple x86_64-pc-windows-msvc -fno-rtti -emit-llvm \
// RUN:   %s -o - | FileCheck %s --check-prefixes=CHECK,DEFAULT
// RUN: %clang_cc1 -triple x86_64-pc-windows-msvc -fno-rtti -emit-llvm \
// RUN:   -fzero-call-used-regs=used-gpr %s -o - | FileCheck %s --check-prefixes=CHECK,REGS

struct Incomplete;
struct A { virtual void f(Incomplete); int a; };
struct B { virtual void f(Incomplete); int b; };
struct C : A, B { [[clang::zeroize_on_return]] void f(Incomplete) override; };
C c;

// An incomplete parameter forces vtable emission to retype the thunk into an
// unprototyped forwarding function. It must not inherit the method's requests.
// CHECK-LABEL: define linkonce_odr {{.*}}void @"?f@C@@WBA@EAAXUIncomplete@@@Z"(
// CHECK-SAME: ptr noundef %this, ...)
// CHECK-SAME: #[[THUNK:[0-9]+]]
// CHECK: musttail call void (ptr, ...) @"?f@C@@UEAAXUIncomplete@@@Z"(
// CHECK-NEXT: ret void

struct D { virtual void f(Incomplete); int d; };
struct E { virtual void f(Incomplete); int e; };
struct F : D, E { void f(Incomplete) override; };
F f;

// Unprotected methods use the same conservative thunk signature and attributes.
// CHECK-LABEL: define linkonce_odr {{.*}}void @"?f@F@@WBA@EAAXUIncomplete@@@Z"(
// CHECK-SAME: ptr noundef %this, ...)
// CHECK-SAME: #[[THUNK]]
// CHECK: musttail call void (ptr, ...) @"?f@F@@UEAAXUIncomplete@@@Z"(
// CHECK-NEXT: ret void

// CHECK: attributes #[[THUNK]] = {
// DEFAULT-NOT: "zero-call-used-regs"
// REGS-SAME: "zero-call-used-regs"="used-gpr"
// CHECK-NOT: "zeroize-stack"
// CHECK-SAME: }
