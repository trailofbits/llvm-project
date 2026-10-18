// RUN: %clang_cc1 -triple x86_64-unknown-linux-gnu -emit-llvm -o - %s | FileCheck %s --check-prefixes=CHECK,LP64
// RUN: %clang_cc1 -triple aarch64-unknown-linux-gnu -emit-llvm -o - %s | FileCheck %s --check-prefixes=CHECK,LP64
// RUN: %clang_cc1 -triple i386-unknown-linux-gnu -emit-llvm -o - %s | FileCheck %s --check-prefixes=CHECK,ILP32
// RUN: %clang_cc1 -triple armv7-unknown-linux-gnueabi -emit-llvm -o - %s | FileCheck %s --check-prefixes=CHECK,ILP32
// RUN: %clang_cc1 -triple x86_64-unknown-linux-gnu -O2 -emit-llvm -o - %s | FileCheck %s --check-prefix=OPT

// The builtin lowers to a volatile llvm.memset.inline of zero: volatile keeps
// the clear from being removed as a dead store, and the inline form keeps it
// from becoming a memset call. The length is size_t wide.

typedef __SIZE_TYPE__ size_t;
void fill(void *);

// CHECK-LABEL: define {{.*}} @variable(
// LP64:  call void @llvm.memset.inline.p0.i64(ptr align 1 %{{.*}}, i8 0, i64 %{{.*}}, i1 true)
// ILP32: call void @llvm.memset.inline.p0.i32(ptr align 1 %{{.*}}, i8 0, i32 %{{.*}}, i1 true)
// OPT-LABEL: define {{.*}} @variable(
// OPT:   call void @llvm.memset.inline.p0.i64(ptr align 1 %p, i8 0, i64 %n, i1 true)
void variable(char *p, size_t n) { __builtin_clear_sensitive(p, n); }

// The alignment comes from the pointee type.
// CHECK-LABEL: define {{.*}} @aligned(
// LP64:  call void @llvm.memset.inline.p0.i64(ptr align 8 %{{.*}}, i8 0, i64 64, i1 true)
// ILP32: call void @llvm.memset.inline.p0.i32(ptr align {{4|8}} %{{.*}}, i8 0, i32 64, i1 true)
void aligned(double *p) { __builtin_clear_sensitive(p, 8 * sizeof(double)); }

// A narrower size operand is widened to size_t.
// CHECK-LABEL: define {{.*}} @narrow_size(
// LP64:  %[[CONV:.*]] = zext i8 %{{.*}} to i64
// LP64:  call void @llvm.memset.inline.p0.i64(ptr align 4 %{{.*}}, i8 0, i64 %[[CONV]], i1 true)
// ILP32: %[[CONV:.*]] = zext i8 %{{.*}} to i32
// ILP32: call void @llvm.memset.inline.p0.i32(ptr align 4 %{{.*}}, i8 0, i32 %[[CONV]], i1 true)
void narrow_size(int *p, unsigned char n) { __builtin_clear_sensitive(p, n); }

// The intrinsic is overloaded on the pointer's address space.
// CHECK-LABEL: define {{.*}} @address_space(
// LP64:  call void @llvm.memset.inline.p1.i64(ptr addrspace(1) align 4 %{{.*}}, i8 0, i64 16, i1 true)
// ILP32: call void @llvm.memset.inline.p1.i32(ptr addrspace(1) align 4 %{{.*}}, i8 0, i32 16, i1 true)
void address_space(__attribute__((address_space(1))) int *p) {
  __builtin_clear_sensitive(p, 16);
}

// A local that is never read after the clear keeps the clear under
// optimization.
// CHECK-LABEL: define {{.*}} @dead_local(
// LP64:  call void @llvm.memset.inline.p0.i64(ptr align {{1|16}} %{{.*}}, i8 0, i64 32, i1 true)
// OPT-LABEL: define {{.*}} @dead_local(
// OPT:   call void @fill(
// OPT:   call void @llvm.memset.inline.p0.i64(ptr nonnull align 16 %key, i8 0, i64 32, i1 true)
// OPT-NEXT: call void @llvm.lifetime.end
void dead_local(void) {
  char key[32];
  fill(key);
  __builtin_clear_sensitive(key, sizeof key);
}

// A local that does not escape may be split into volatile stores, which also
// survive.
// OPT-LABEL: define {{.*}} @nonescaping(
// OPT-COUNT-8: {{store volatile i32 0|call void @llvm.memset.inline}}
// OPT:   ret void
void nonescaping(int v) {
  int key[8];
  for (int i = 0; i < 8; ++i)
    key[i] = v;
  __builtin_clear_sensitive(key, sizeof key);
}
