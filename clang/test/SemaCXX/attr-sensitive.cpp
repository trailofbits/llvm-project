// RUN: %clang_cc1 -fsyntax-only -verify -std=c++11 %s
// RUN: %clang_cc1 -fsyntax-only -verify -std=c++23 %s

#if !__has_attribute(sensitive) || !__has_cpp_attribute(clang::sensitive)
#error sensitive is not available
#endif

template <typename T> [[clang::zeroize_on_return]] void protected_template() {
  [[clang::sensitive]] T value;
}
template void protected_template<int>();

struct Methods {
  [[clang::zeroize_on_return]] void method() {
    [[clang::sensitive]] int value;
    [[clang::sensitive]] int &reference = value;
    auto nested = [] {
      // expected-warning@+1 {{has no effect without 'zeroize_on_return'}}
      [[clang::sensitive]] int value;
    };
  }
  // expected-error@+1 {{'clang::sensitive' attribute only applies to local variables}}
  [[clang::sensitive]] int member;
};

template <typename T> void unprotected_template() {
  [[clang::sensitive]] T value; // expected-warning {{has no effect without 'zeroize_on_return'}}
}
template void unprotected_template<int>();

#pragma clang attribute push(__attribute__((zeroize_on_return)), apply_to = function)
void pragma_function() {
  [[clang::sensitive]] int value;
}
#pragma clang attribute pop

[[clang::zeroize_on_return]] void pragma_local() {
#pragma clang attribute push(__attribute__((sensitive)), apply_to = variable(is_local))
  int value;
#pragma clang attribute pop
}
