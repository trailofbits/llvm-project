// RUN: %clang_cc1 -std=c++11 -ast-dump %s | FileCheck %s
// RUN: %clang_cc1 -std=c++11 -emit-pch -o %t %s
// RUN: %clang_cc1 -std=c++11 -x c++ -include-pch %t -ast-dump-all /dev/null \
// RUN:   | FileCheck %s

[[clang::zeroize_on_return]] void redeclared();
void redeclared() {}
// CHECK-LABEL: FunctionDecl{{.*}} redeclared 'void ()'
// CHECK: ZeroizeOnReturnAttr
// CHECK-LABEL: FunctionDecl{{.*}} redeclared 'void ()'
// CHECK: ZeroizeOnReturnAttr{{.*}} Inherited

template <class T>
[[clang::zeroize_on_return]] void instantiated(T) {}
template void instantiated<int>(int);
// CHECK-LABEL: FunctionTemplateDecl{{.*}} instantiated
// CHECK: FunctionDecl{{.*}} instantiated 'void (T)'
// CHECK: ZeroizeOnReturnAttr
// CHECK: FunctionDecl{{.*}} instantiated 'void (int)'
// CHECK: ZeroizeOnReturnAttr

struct Annotated {
  [[clang::zeroize_on_return]] void member();
};
void Annotated::member() {}
// CHECK-LABEL: CXXRecordDecl{{.*}} struct Annotated definition
// CHECK-LABEL: CXXMethodDecl{{.*}} member 'void ()'
// CHECK: ZeroizeOnReturnAttr
// CHECK-LABEL: CXXMethodDecl{{.*}} member 'void ()'
// CHECK: ZeroizeOnReturnAttr{{.*}} Inherited

#pragma clang attribute push(__attribute__((zeroize_on_return)), apply_to = function)
void from_pragma() {}
#pragma clang attribute pop
// CHECK-LABEL: FunctionDecl{{.*}} from_pragma 'void ()'
// CHECK: ZeroizeOnReturnAttr
