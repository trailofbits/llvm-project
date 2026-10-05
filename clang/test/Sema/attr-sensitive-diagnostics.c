// RUN: %clang_cc1 -fsyntax-only -verify=warning %s
// RUN: %clang_cc1 -fsyntax-only -Wno-ignored-attributes -verify=quiet %s
// RUN: %clang_cc1 -fsyntax-only -Werror=ignored-attributes -verify=error %s

// quiet-no-diagnostics
void stray(void) {
  // warning-warning@+2 {{has no effect without 'zeroize_on_return'}}
  // error-error@+1 {{has no effect without 'zeroize_on_return'}}
  int value __attribute__((sensitive));
}
