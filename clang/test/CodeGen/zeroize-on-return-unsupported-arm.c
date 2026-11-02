// REQUIRES: arm-registered-target
// RUN: %clang_cc1 -triple armv7-unknown-linux-gnueabi -S -verify %s -o /dev/null

// expected-warning@+2 {{"zeroize-stack" is not supported by this target}}
// expected-error@+1 {{"zero-call-used-regs" is not supported by this target}}
[[clang::zeroize_on_return]] void unsupported(void) {
  [[clang::sensitive]] volatile int key = 42;
}
