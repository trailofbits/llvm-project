// RUN: %clang_cc1 -triple amdgcn-amd-amdhsa -emit-llvm -o - %s | FileCheck %s
// RUN: %clang_cc1 -triple amdgcn-amd-amdhsa -emit-llvm -o - %s | llvm-as -o /dev/null

void use(void *);

// CHECK-LABEL: define {{.*}} @address_spaces(
// CHECK: %secret = alloca i32, align 4, addrspace(5){{$}}
// CHECK: %ordinary = alloca i32, align 4, addrspace(5), !nozeroize ![[EMPTY:[0-9]+]]{{$}}
// CHECK: addrspacecast ptr addrspace(5) %secret to ptr
// CHECK: addrspacecast ptr addrspace(5) %ordinary to ptr
__attribute__((zeroize_on_return)) void address_spaces(void) {
  int secret __attribute__((sensitive));
  int ordinary;
  use(&secret);
  use(&ordinary);
}

// CHECK: ![[EMPTY]] = !{}
