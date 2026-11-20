// REQUIRES: aarch64-registered-target || x86-registered-target || arm-registered-target
// RUN: %if aarch64-registered-target %{ %clang_cc1 -triple aarch64-unknown-linux-gnu \
// RUN:   -S -verify=warning %s -o /dev/null %}
// RUN: %if aarch64-registered-target %{ %clang_cc1 -triple aarch64-unknown-linux-gnu \
// RUN:   -S -Werror -verify=error %s -o /dev/null %}
// RUN: %if x86-registered-target %{ %clang_cc1 -triple x86_64-unknown-linux-gnu \
// RUN:   -S -target-feature +sahf -verify=supported %s -o /dev/null %}
// RUN: %if x86-registered-target %{ %clang_cc1 -triple x86_64-unknown-linux-gnu \
// RUN:   -S -target-feature -sahf -verify=flags %s -o /dev/null %}
// RUN: %if x86-registered-target %{ %clang_cc1 -triple x86_64-apple-darwin \
// RUN:   -S -target-feature +sahf -verify=warning,x86 %s -o /dev/null %}
// RUN: %if x86-registered-target %{ %clang_cc1 -triple x86_64-apple-darwin \
// RUN:   -S -Werror -target-feature +sahf -verify=error,x86 %s -o /dev/null %}
// RUN: %if arm-registered-target %{ %clang_cc1 -triple armv7-unknown-linux-gnueabi \
// RUN:   -S -verify=supported %s -o /dev/null %}
// RUN: %if arm-registered-target %{ %clang_cc1 -triple armv7-unknown-linux-gnueabi \
// RUN:   -S -Werror -verify=supported %s -o /dev/null %}

// ARM and X86 ELF with SAHF support this static frame and flags clearing.
// Unsupported requests are diagnosed; X86 also rejects unsupported frame layouts.
// supported-no-diagnostics
// warning-warning@+6 {{"zeroize-stack" is not supported by this target}}
// warning-error@+5 {{"zeroize-flags" is not supported by this target or exit protocol}}
// error-error@+4 {{"zeroize-stack" is not supported by this target}}
// error-error@+3 {{"zeroize-flags" is not supported by this target or exit protocol}}
// flags-error@+2 {{"zeroize-flags" is not supported by this target or exit protocol}}
// x86-error@+1 {{X86 stack clearing does not support this frame, calling convention, or exit}}
[[clang::zeroize_on_return]] void unsupported(void) {
  [[clang::sensitive]] volatile int key = 42;
}
