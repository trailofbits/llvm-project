// RUN: %clang_cc1 -fsyntax-only -verify -std=c23 %s
// RUN: %clang_cc1 -fsyntax-only -verify -std=c99 %s

#if !__has_attribute(sensitive) || !__has_c_attribute(clang::sensitive)
#error sensitive is not available
#endif

[[clang::zeroize_on_return]] void protected(void) {
  [[clang::sensitive]] int scalar;
  unsigned char array[32] __attribute__((sensitive));
  int *pointer __attribute__((sensitive));
  // expected-error@+1 {{'sensitive' attribute takes no arguments}}
  int bad __attribute__((sensitive(1)));
  // expected-error@+1 {{'sensitive' attribute only applies to local variables}}
  static int persistent __attribute__((sensitive));
  // expected-error@+1 {{'sensitive' attribute only applies to local variables}}
  extern int external __attribute__((sensitive));
}

[[clang::zeroize_on_return]] void redeclared(void);
void redeclared(void) {
  [[clang::sensitive]] int inherited;
}

void stray(void) {
  [[clang::sensitive]] int scalar; // expected-warning {{has no effect without 'zeroize_on_return'}}
  // expected-warning@+1 {{has no effect without 'zeroize_on_return'}}
  int other __attribute__((sensitive));
}

__attribute__((zero_call_used_regs("all"))) void registers_only(void) {
  // expected-warning@+1 {{has no effect without 'zeroize_on_return'}}
  int scalar __attribute__((sensitive));
}

// expected-error@+1 {{'sensitive' attribute only applies to local variables}}
int global __attribute__((sensitive));
// expected-error@+1 {{'sensitive' attribute only applies to local variables}}
void function(void) __attribute__((sensitive));
// expected-error@+1 {{'sensitive' attribute only applies to local variables}}
void parameter(int value __attribute__((sensitive)));
// expected-error@+1 {{'sensitive' attribute only applies to local variables}}
typedef int type __attribute__((sensitive));
struct Fields {
  // expected-error@+1 {{'sensitive' attribute only applies to local variables}}
  int field __attribute__((sensitive));
};
