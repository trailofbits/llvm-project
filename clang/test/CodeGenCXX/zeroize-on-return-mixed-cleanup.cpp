// REQUIRES: x86-registered-target || aarch64-registered-target
// RUN: %if x86-registered-target %{ %clang --target=x86_64-linux-gnu -O2 -msahf -fexceptions -Werror \
// RUN:   -mllvm -verify-machineinstrs -DPROTECTED -S %s -o - | FileCheck %s %}
// RUN: %if aarch64-registered-target %{ %clang --target=aarch64-linux-gnu -O2 -fexceptions -Werror \
// RUN:   -mllvm -verify-machineinstrs -DPROTECTED -S %s -o - | FileCheck %s --check-prefix=A64 %}

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

// A64-LABEL: mixed:
// A64: bl record_cleanup
// A64: stp xzr, xzr,
// A64: msr NZCV, xzr
// A64-NEXT: ret
// A64: bl __cxa_begin_catch
// A64: bl action
// A64: bl record_cleanup
// A64: stp xzr, xzr,
// A64: adrp x1, .Lzeroize_resume_[[CONT:[0-9]+]]
// A64-NEXT: add x1, x1, :lo12:.Lzeroize_resume_[[CONT]]
// A64: msr NZCV, xzr
// A64-NEXT: b .Lzeroize_resume_thunk[[THUNK:[0-9]+]]
// A64: .Lzeroize_resume_[[CONT]]:
// A64: .Lzeroize_resume_thunk[[THUNK]]:
// A64: bl _Unwind_Resume
