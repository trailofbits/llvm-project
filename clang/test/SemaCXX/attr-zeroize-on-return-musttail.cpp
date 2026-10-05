// RUN: %clang_cc1 -triple x86_64-unknown-linux-gnu -std=c++11 -fsyntax-only -verify %s
// RUN: %clang_cc1 -triple x86_64-unknown-linux-gnu -std=c++11 -emit-llvm -verify %s -o /dev/null

int callee(int);

struct Methods {
  int callee(int);
  [[clang::zeroize_on_return]] // expected-note{{'zeroize_on_return' attribute specified here}}
  int tail(int x) {
    // expected-error@+1{{'musttail' cannot be used in a function with 'zeroize_on_return'}}
    [[clang::musttail]] return callee(x);
  }
};

template <class T>
[[clang::zeroize_on_return]] // expected-note{{'zeroize_on_return' attribute specified here}}
T protected_template(T x) {
  // expected-error@+1{{'musttail' cannot be used in a function with 'zeroize_on_return'}}
  [[clang::musttail]] return callee(x);
}

int instantiate(int x) {
  // expected-note@+1{{in instantiation of function template specialization}}
  return protected_template(x);
}

[[clang::zeroize_on_return]]
int nested_method(int x) {
  struct Callable {
    int operator()(int y) {
      [[clang::musttail]] return operator()(y);
    }
  };
  return Callable{}(x);
}
