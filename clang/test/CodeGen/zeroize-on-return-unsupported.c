// REQUIRES: aarch64-registered-target || x86-registered-target || arm-registered-target
// RUN: %if aarch64-registered-target %{ %clang_cc1 -triple aarch64-unknown-linux-gnu \
// RUN:   -S -verify=warning %s -o /dev/null %}
// RUN: %if aarch64-registered-target %{ %clang_cc1 -triple aarch64-unknown-linux-gnu \
// RUN:   -S -Werror -verify=error %s -o /dev/null %}
// RUN: %if x86-registered-target %{ %clang_cc1 -triple x86_64-unknown-linux-gnu \
// RUN:   -S -verify=warning %s -o /dev/null %}
// RUN: %if x86-registered-target %{ %clang_cc1 -triple x86_64-unknown-linux-gnu \
// RUN:   -S -Werror -verify=error %s -o /dev/null %}
// RUN: %if arm-registered-target %{ %clang_cc1 -triple armv7-unknown-linux-gnueabi \
// RUN:   -S -verify=arm %s -o /dev/null %}
// RUN: %if arm-registered-target %{ %clang_cc1 -triple armv7-unknown-linux-gnueabi \
// RUN:   -S -Werror -verify=arm %s -o /dev/null %}

// ARM supports this static frame and flags clearing. X86 and AArch64 diagnose
// the stack request as a warning and the flags request as an error.
// arm-no-diagnostics
// warning-warning@+4 {{"zeroize-stack" is not supported by this target}}
// warning-error@+3 {{"zeroize-flags" is not supported by this target or exit protocol}}
// error-error@+2 {{"zeroize-stack" is not supported by this target}}
// error-error@+1 {{"zeroize-flags" is not supported by this target or exit protocol}}
[[clang::zeroize_on_return]] void unsupported(void) {
  [[clang::sensitive]] volatile int key = 42;
}
