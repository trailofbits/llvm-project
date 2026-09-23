// The backend clears the call-used registers on 32-bit Arm, in each of its
// three instruction-set modes, so the driver no longer refuses the request.

// REQUIRES: arm-registered-target

// RUN: %clang -### --target=arm-none-eabi -fzero-call-used-regs=used-gpr -S %s 2>&1 | FileCheck %s
// RUN: %clang -### --target=armeb-none-eabi -fzero-call-used-regs=all -S %s 2>&1 | FileCheck %s
// RUN: %clang -### --target=thumbv7m-none-eabi -fzero-call-used-regs=all -S %s 2>&1 | FileCheck %s
// RUN: %clang -### --target=thumbv6m-none-eabi -fzero-call-used-regs=used -S %s 2>&1 | FileCheck %s

// CHECK-NOT: error: unsupported option
// CHECK: "-fzero-call-used-regs=

// A target whose backend does not implement the clear is still refused, which
// is what keeps the check above from passing for the wrong reason.
// RUN: not %clang -### --target=powerpc64-unknown-linux-gnu -fzero-call-used-regs=all -S %s 2>&1 | \
// RUN:   FileCheck %s --check-prefix=REFUSED
// REFUSED: error: unsupported option '-fzero-call-used-regs=all' for target

// Compile through PEI as well: driver acceptance alone does not establish
// that the backend opted into register clearing.
// RUN: %clang --target=armv7-none-eabi -O2 -fzero-call-used-regs=all-gpr -S %s -o - | FileCheck %s --check-prefix=ASM
// RUN: %clang --target=thumbv7m-none-eabi -O2 -fzero-call-used-regs=all-gpr -S %s -o - | FileCheck %s --check-prefix=ASM
// RUN: %clang --target=thumbv6m-none-eabi -O2 -fzero-call-used-regs=all-gpr -S %s -o - | FileCheck %s --check-prefix=ASM
// ASM-LABEL: clear_regs:
// ASM: mov{{s?}} r0, #0
// ASM: bx lr
void clear_regs(void) {}
