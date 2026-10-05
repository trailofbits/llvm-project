// RUN: %clang_cc1 -triple x86_64-apple-darwin -fblocks -emit-llvm \
// RUN:   -o - %s | FileCheck %s

void use_block(void (^)(void));

// CHECK-LABEL: define {{.*}} @byref(
// CHECK: %value = alloca %struct.__block_byref_value, align 8{{$}}
// CHECK: %secret = alloca %struct.__block_byref_secret{{.*}}, align 8{{$}}
// CHECK: %ordinary = alloca i32, align 4, !nozeroize ![[EMPTY:[0-9]+]]{{$}}
// CHECK: %block = alloca {{.*}}, align 8{{$}}
__attribute__((zeroize_on_return)) void byref(void) {
  __block int value;
  __block int secret __attribute__((sensitive));
  int ordinary;
  use_block(^{ value = ordinary; secret = 1; });
}

// CHECK: ![[EMPTY]] = !{}
