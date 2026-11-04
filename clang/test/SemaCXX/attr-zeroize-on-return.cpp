// RUN: %clang_cc1 -fsyntax-only -verify -std=c++11 %s

#if !__has_cpp_attribute(clang::zeroize_on_return)
#error "clang::zeroize_on_return is not available via __has_cpp_attribute"
#endif

[[clang::zeroize_on_return]] void free_function() {}
__attribute__((zeroize_on_return)) void gnu_free_function() {}

struct S {
  [[clang::zeroize_on_return]] void member();
  [[clang::zeroize_on_return]] static void static_member() {}
  // expected-error@+1 {{'clang::zeroize_on_return' attribute only applies to functions}}
  [[clang::zeroize_on_return]] int field;
};

[[clang::zeroize_on_return]] void S::member() {}

template <typename T> [[clang::zeroize_on_return]] void tmpl(T) {}
template void tmpl<int>(int);

void lambda() {
  auto l = []() __attribute__((zeroize_on_return)) {};
  l();
}

// expected-error@+1 {{'clang::zeroize_on_return' attribute only applies to functions}}
class [[clang::zeroize_on_return]] C {};

namespace N {
// expected-error@+1 {{'clang::zeroize_on_return' attribute only applies to functions}}
[[clang::zeroize_on_return]] int variable;
}

// No mode argument is accepted in the C++ spelling either.
// expected-error@+1 {{'clang::zeroize_on_return' attribute takes no arguments}}
[[clang::zeroize_on_return("all")]] void with_mode();

// Repeating the same request is harmless.
[[clang::zeroize_on_return, clang::zeroize_on_return]] void repeated();
