// REQUIRES: arm-registered-target
// RUN: %clang_cc1 -triple thumbv7-pc-windows-msvc -S -verify %s -o /dev/null

// Windows ARM still lacks register clearing; ELF ARM is covered by
// zeroize-on-return-unsupported.c and only diagnoses unsupported stack clearing.
// expected-warning@+2 {{"zeroize-stack" is not supported by this target}}
// expected-error@+1 {{"zero-call-used-regs" is not supported by this target}}
[[clang::zeroize_on_return]] void unsupported(void) {
  [[clang::sensitive]] volatile int key = 42;
}
