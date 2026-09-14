// REQUIRES: arm-registered-target
// RUN: %clang --target=armv7-none-eabi -O2 -S %s -o - | FileCheck %s --check-prefix=ATTR
// RUN: %clang --target=thumbv6m-none-eabi -O2 -S %s -o - | FileCheck %s --check-prefix=ATTR
// RUN: %clang --target=thumbv7m-none-eabi -O2 -S %s -o - | FileCheck %s --check-prefix=ATTR
// RUN: %clang --target=armv7-none-eabi -O2 -fzero-call-used-regs=all-gpr -S %s -o - | FileCheck %s --check-prefix=FLAG
// RUN: %clang --target=thumbv6m-none-eabi -O2 -fzero-call-used-regs=all-gpr -S %s -o - | FileCheck %s --check-prefix=FLAG
// RUN: %clang --target=thumbv7m-none-eabi -O2 -fzero-call-used-regs=all-gpr -S %s -o - | FileCheck %s --check-prefix=FLAG

// Exercise code generation, not just the driver's -### output. Both request
// paths must reach the target emitter, while an explicit skip still opts out.

// ATTR-LABEL: attributed:
// ATTR: mov{{.*}} r12,
// ATTR: bx lr
__attribute__((zero_call_used_regs("all-gpr")))
int attributed(int x) { return x; }

// FLAG-LABEL: flag_enabled:
// FLAG: mov{{.*}} r12,
// FLAG: bx lr
int flag_enabled(int x) { return x; }

// FLAG-LABEL: skipped:
// FLAG-NOT: mov
// FLAG: bx lr
__attribute__((zero_call_used_regs("skip")))
int skipped(int x) { return x; }
