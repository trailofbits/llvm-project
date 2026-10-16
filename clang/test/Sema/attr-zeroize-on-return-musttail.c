// RUN: %clang_cc1 -triple x86_64-unknown-linux-gnu -fsyntax-only -verify %s

int callee(int);

__attribute__((zeroize_on_return)) // expected-note{{'zeroize_on_return' attribute specified here}}
int protected_tail(int x) {
  // expected-error@+1{{'musttail' cannot be used in a function with 'zeroize_on_return'}}
  __attribute__((musttail)) return callee(x);
}

__attribute__((zeroize_on_return)) // expected-note{{'zeroize_on_return' attribute specified here}}
int inherited_tail(int);
int inherited_tail(int x) {
  // expected-error@+1{{'musttail' cannot be used in a function with 'zeroize_on_return'}}
  __attribute__((musttail)) return callee(x);
}

int ordinary_tail(int x) { // expected-note{{previous definition is here}}
  __attribute__((musttail)) return callee(x);
}

__attribute__((zeroize_on_return))
int ordinary_return(int x) {
  return callee(x);
}

// Adding the attribute after a completed musttail body is already diagnosed.
// expected-warning@+1{{attribute declaration must precede definition}}
__attribute__((zeroize_on_return)) int ordinary_tail(int);
