// REQUIRES: aarch64-registered-target
// RUN: %clang_cc1 -triple aarch64-unknown-linux-gnu -S -verify=warning %s -o /dev/null
// RUN: %clang_cc1 -triple aarch64-unknown-linux-gnu -S -Werror -verify=error %s -o /dev/null

// warning-warning@+2 {{"zeroize-stack" is not supported by this target}}
// error-error@+1 {{"zeroize-stack" is not supported by this target}}
[[clang::zeroize_on_return]] void unsupported(void) {
  [[clang::sensitive]] volatile int key = 42;
}

// warning-warning@+4 {{"zeroize-stack" ignored on a "naked" function}}
// warning-warning@+3 {{"zero-call-used-regs" ignored on a "naked" function}}
// error-error@+2 {{"zeroize-stack" ignored on a "naked" function}}
// error-error@+1 {{"zero-call-used-regs" ignored on a "naked" function}}
__attribute__((zeroize_on_return, naked)) void naked_function(void) {
  __asm__("");
}
