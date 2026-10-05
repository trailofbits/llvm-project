// RUN: %clang_cc1 -triple x86_64-unknown-linux-gnu -std=c++11 -emit-llvm \
// RUN:   -o - %s | FileCheck %s
// RUN: %clang_cc1 -triple x86_64-unknown-linux-gnu -std=c++11 -emit-llvm \
// RUN:   -o - %s | llvm-as -o /dev/null
// RUN: %clang_cc1 -triple x86_64-unknown-linux-gnu -std=c++11 \
// RUN:   -emit-pch -o %t %s
// RUN: %clang_cc1 -triple x86_64-unknown-linux-gnu -std=c++11 \
// RUN:   -include-pch %t -emit-llvm -x c++ -o - /dev/null | FileCheck %s

void use(void *);

// CHECK-LABEL: define {{.*}} @_Z10referencesv(
// CHECK: %secret = alloca i32, align 4{{$}}
// CHECK: %ordinary = alloca i32, align 4, !nozeroize ![[EMPTY:[0-9]+]]{{$}}
// CHECK: %secret_ref = alloca ptr, align 8{{$}}
// CHECK: %ordinary_ref = alloca ptr, align 8, !nozeroize ![[EMPTY]]{{$}}
[[clang::zeroize_on_return]] void references() {
  [[clang::sensitive]] int secret;
  int ordinary;
  [[clang::sensitive]] int &secret_ref = secret;
  int &ordinary_ref = ordinary;
  use(&secret_ref);
  use(&ordinary_ref);
}

struct Result { int data[16]; };

// CHECK-LABEL: define {{.*}} @_Z6resultv(
// CHECK-NOT: !nozeroize
// CHECK: ret void
[[clang::zeroize_on_return]] Result result() {
  Result value;
  use(&value);
  return value;
}

// CHECK-LABEL: define {{.*}} @_Z9range_forv(
// CHECK: %values = alloca [4 x i32], align 16{{$}}
// CHECK: %__range1 = alloca ptr, align 8{{$}}
// CHECK: %__begin1 = alloca ptr, align 8{{$}}
// CHECK: %__end1 = alloca ptr, align 8{{$}}
// CHECK: %value = alloca ptr, align 8{{$}}
[[clang::zeroize_on_return]] void range_for() {
  [[clang::sensitive]] int values[4];
  for ([[clang::sensitive]] int &value : values)
    use(&value);
}

// Captures do not propagate the annotation; the closure needs its own mark.
// CHECK-LABEL: define {{.*}} @_Z8closuresv(
// CHECK: %key = alloca i32, align 4{{$}}
// CHECK: %ordinary = alloca %class.anon, align 4, !nozeroize ![[EMPTY]]{{$}}
// CHECK: %secret = alloca %class.anon.0, align 4{{$}}
[[clang::zeroize_on_return]] void closures() {
  [[clang::sensitive]] int key = 42;
  auto ordinary = [key] { return key; };
  [[clang::sensitive]] auto secret = [key] { return key; };
  use(&ordinary);
  use(&secret);
}

template <typename T> [[clang::zeroize_on_return]] void mixed_template() {
  [[clang::sensitive]] T secret;
  T ordinary;
  use(&secret);
  use(&ordinary);
}
template void mixed_template<int>();

// CHECK-LABEL: define {{.*}} @_Z14mixed_templateIiEvv(
// CHECK: %secret = alloca i32, align 4{{$}}
// CHECK: %ordinary = alloca i32, align 4, !nozeroize ![[EMPTY]]{{$}}
// CHECK: ![[EMPTY]] = !{}
