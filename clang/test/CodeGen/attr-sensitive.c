// RUN: %clang_cc1 -triple x86_64-unknown-linux-gnu -std=c23 -emit-llvm \
// RUN:   -Wno-ignored-attributes -o - %s | FileCheck %s
// RUN: %clang_cc1 -triple x86_64-unknown-linux-gnu -std=c23 -emit-llvm \
// RUN:   -Wno-ignored-attributes -fzero-call-used-regs=skip -o - %s | FileCheck %s
// RUN: %clang_cc1 -triple x86_64-unknown-linux-gnu -std=c23 -emit-llvm \
// RUN:   -Wno-ignored-attributes -o - %s | llvm-as -o /dev/null

void use(void *);

// CHECK-LABEL: define {{.*}} @mixed(
// CHECK: %secret = alloca [32 x i8], align 16{{$}}
// CHECK: %scratch = alloca [64 x i8], align 16, !nozeroize ![[EMPTY:[0-9]+]]{{$}}
// CHECK: %pointer = alloca ptr, align 8{{$}}
// CHECK: %ordinary = alloca ptr, align 8, !nozeroize ![[EMPTY]]{{$}}
[[clang::zeroize_on_return]] void mixed(void) {
  [[clang::sensitive]] unsigned char secret[32];
  unsigned char scratch[64];
  void *pointer __attribute__((sensitive)) = secret;
  void *ordinary = scratch;
  use(pointer);
  use(ordinary);
}

// CHECK-LABEL: define {{.*}} @dynamic(
// CHECK: %n.addr = alloca i32, align 4{{$}}
// CHECK: %saved_stack = alloca ptr, align 8{{$}}
// CHECK: %vla = alloca i32, i64 %{{.*}}, align 16{{$}}
// CHECK: %vla{{[0-9]+}} = alloca i32, i64 %{{.*}}, align 16, !nozeroize ![[EMPTY]]{{$}}
[[clang::zeroize_on_return]] void dynamic(int n) {
  [[clang::sensitive]] int secret[n];
  int scratch[n];
  use(secret);
  use(scratch);
}

// CHECK-LABEL: define {{.*}} @stray(
// CHECK: %secret = alloca i32, align 4{{$}}
// CHECK: %ordinary = alloca i32, align 4{{$}}
void stray(void) {
  int secret __attribute__((sensitive));
  int ordinary;
  use(&secret);
  use(&ordinary);
}

// CHECK-LABEL: define {{.*}} @registers_only(
// CHECK: %ordinary = alloca i32, align 4{{$}}
__attribute__((zero_call_used_regs("all"))) void registers_only(void) {
  int ordinary;
  use(&ordinary);
}

// CHECK-LABEL: define {{.*}} @inherited(
// CHECK: %secret = alloca i32, align 4{{$}}
// CHECK: %ordinary = alloca i32, align 4, !nozeroize ![[EMPTY]]{{$}}
[[clang::zeroize_on_return]] void inherited(void);
void inherited(void) {
  [[clang::sensitive]] int secret;
  int ordinary;
  use(&secret);
  use(&ordinary);
}

// CHECK: ![[EMPTY]] = !{}
