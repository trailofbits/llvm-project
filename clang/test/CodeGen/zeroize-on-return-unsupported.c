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
