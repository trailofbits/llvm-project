// REQUIRES: arm-registered-target || aarch64-registered-target || x86-registered-target
// DEFINE: %{compile} = %clang -O2 -fexceptions -S %s
// DEFINE: %{protect} = -DPROTECTED -mllvm -verify-machineinstrs
// DEFINE: %{arm} = %{compile} --target=armv7-linux-gnueabihf -marm -mfpu=neon
// DEFINE: %{a64} = %{compile} --target=aarch64-linux-gnu
// RUN: %if arm-registered-target %{ %{arm} -o - | FileCheck %s --check-prefix=ARM-CONTROL %}
// RUN: %if arm-registered-target %{ not %{arm} %{protect} -o %t.s 2>&1 \
// RUN:   | FileCheck %s --check-prefix=ARM-ERROR %}
// RUN: %if aarch64-registered-target %{ %{a64} -o - | FileCheck %s --check-prefix=A64-CONTROL %}
// RUN: %if aarch64-registered-target %{ not %{a64} %{protect} -o %t.s 2>&1 \
// RUN:   | FileCheck %s --check-prefix=A64-ERROR %}
// RUN: %if aarch64-registered-target %{ %{compile} --target=aarch64-linux-android29 \
// RUN:   -ffixed-x18 -fsanitize=shadow-call-stack -funwind-tables %{protect} -o - \
// RUN:   | FileCheck %s --check-prefix=ANDROID %}
// RUN: %if x86-registered-target %{ %{compile} --target=x86_64-linux-gnu -msahf %{protect} \
// RUN:   -o - | FileCheck %s --check-prefix=X86 %}

extern "C" void record_cleanup() noexcept;
extern "C" void may_throw();

struct Guard {
  ~Guard() { record_cleanup(); }
};

extern "C"
#ifdef PROTECTED
[[clang::zeroize_on_return]]
#endif
unsigned outgoing(unsigned value) {
  Guard guard;
  volatile unsigned saved = value;
  may_throw();
  return saved + 3;
}

// The control compilers emit the cleanup call for the same source.
// ARM-CONTROL: bl record_cleanup
// ARM-CONTROL: bl __cxa_end_cleanup
// ARM-ERROR: error: ARM stack clearing does not support
// A64-CONTROL: bl record_cleanup
// A64-CONTROL: bl _Unwind_Resume
// A64-ERROR: error: AArch64 stack clearing does not support

// Start past the ordinary return so that an earlier clear cannot satisfy
// the checks for the destructor's outgoing cleanup.
// ANDROID-LABEL: outgoing:
// ANDROID: str x30, [x18], #8
// ANDROID: ret
// ANDROID: bl record_cleanup
// ANDROID: .cfi_escape 0x10, 0x1e, 0x02, 0x82, 0x78
// ANDROID: stp xzr, xzr,
// ANDROID: msr NZCV, xzr
// ANDROID-NEXT: bl _Unwind_Resume
// X86-LABEL: outgoing:
// X86: retq
// X86: callq record_cleanup
// X86: movq $0, ({{%r[a-z0-9]+}})
// X86: testl %eax, %eax
// X86-NEXT: sahf
// X86-NEXT: callq _Unwind_Resume
