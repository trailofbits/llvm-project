// REQUIRES: x86-registered-target
// RUN: %clang --target=x86_64-linux-gnu -O2 -msahf -fexceptions -Werror \
// RUN:   -mllvm -verify-machineinstrs -DPROTECTED -S %s -o - | FileCheck %s

extern "C" void action(unsigned);
extern "C" void record_cleanup() noexcept;

struct Guard {
  ~Guard() { record_cleanup(); }
};

extern "C"
#ifdef PROTECTED
[[clang::zeroize_on_return]]
#endif
unsigned mixed(unsigned Mode) {
  Guard G;
  volatile unsigned Value = 10 + Mode;
  try {
    action(Mode);
  } catch (int N) {
    action(Mode + 10);
    return Value + unsigned(N);
  }
  return Value;
}

// Ordinary and locally caught paths share a return. An unmatched exception
// or a throw from the handler reaches the cleanup that resumes unwinding.
// CHECK-LABEL: mixed:
// CHECK: callq record_cleanup
// CHECK: movq $0, (%rsp)
// CHECK: sahf
// CHECK: retq
// CHECK: callq __cxa_begin_catch
// CHECK: callq action
// CHECK: callq record_cleanup
// CHECK: movq $0, (%rsp)
// CHECK: testl %eax, %eax
// CHECK-NEXT: sahf
// CHECK-NEXT: callq _Unwind_Resume
