// REQUIRES: arm-registered-target
// DEFINE: %{compile} = %clang --target=armv7-linux-gnueabihf -mfpu=neon -O1 -fomit-frame-pointer -mllvm -verify-machineinstrs %s
// RUN: %{compile} -S -marm -o - | FileCheck %s
// RUN: %{compile} -S -mthumb -o - | FileCheck %s
// RUN: %{compile} -mthumb -c -o %t.o
// RUN: not %{compile} -S -ffixed-r9 -o %t.s 2>&1 | FileCheck %s --check-prefix=REJECT
// RUN: %{compile} -S -ffixed-r9 -DNO_THROW -o - | FileCheck %s --check-prefix=ORDINARY
// RUN: not %{compile} -S -fno-omit-frame-pointer -o %t.s 2>&1 | FileCheck %s --check-prefix=REJECT
// RUN: not %{compile} -S -DWITH_CATCH -o %t.s 2>&1 | FileCheck %s --check-prefix=REJECT
// RUN: %{compile} -S -DCATCH_RETURN_ONLY -o - | FileCheck %s --check-prefix=ORDINARY

#ifdef NO_THROW
extern "C" void action() noexcept;
#else
extern "C" void action();
#endif
extern "C" void cleanup_event() noexcept;
struct Guard {
  ~Guard() { cleanup_event(); }
};

extern "C" [[clang::zeroize_on_return]] int protected_cleanup(int value) {
#ifdef CATCH_RETURN_ONLY
  try {
    action();
    return value;
  } catch (...) {
    return 7;
  }
#else
  volatile unsigned words[6];
  words[1] = value;
  asm volatile("" : : "r"(words) : "r4", "memory");
  Guard guard;
#ifdef WITH_CATCH
  try {
    action();
  } catch (...) {
    action();
  }
#else
  action();
#endif
  return words[1];
#endif
}

// CHECK-LABEL: protected_cleanup:
// CHECK: .save {r4, lr}
// CHECK: bx lr
// CHECK: bl cleanup_event
// CHECK: movw r1, :lower16:(.Larm_zeroize_continuation_0-
// CHECK: movw r12, :lower16:(.Larm_zeroize_carrier_0-
// CHECK: msr APSR_nzcvq,
// CHECK-NEXT: bx r12
// CHECK: .personality .Larm_zeroize_personality_0
// CHECK: .Larm_zeroize_carrier_0:
// CHECK: bl __cxa_end_cleanup
// REJECT: error: ARM stack clearing does not support
// REJECT-NOT: Assertion
// ORDINARY-LABEL: protected_cleanup:
// ORDINARY: msr APSR_nzcvq,
// ORDINARY: bx lr
// ORDINARY-NOT: .Larm_zeroize_
