// REQUIRES: aarch64-registered-target || x86-registered-target
// RUN: %if aarch64-registered-target %{ %clang_cc1 -triple aarch64-unknown-linux-gnu \
// RUN:   -S -verify=warning %s -o /dev/null %}
// RUN: %if aarch64-registered-target %{ %clang_cc1 -triple aarch64-unknown-linux-gnu \
// RUN:   -S -Werror -verify=error %s -o /dev/null %}
// RUN: %if x86-registered-target %{ %clang_cc1 -triple x86_64-unknown-linux-gnu \
// RUN:   -S -verify=warning %s -o /dev/null %}
// RUN: %if x86-registered-target %{ %clang_cc1 -triple x86_64-unknown-linux-gnu \
// RUN:   -S -Werror -verify=error %s -o /dev/null %}

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
