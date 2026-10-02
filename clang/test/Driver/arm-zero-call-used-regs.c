// The backend clears the call-used registers on 32-bit Arm, in each of its
// three instruction-set modes, so the driver no longer refuses the request.

// RUN: %clang -### --target=arm-none-eabi -fzero-call-used-regs=used-gpr -S %s 2>&1 | FileCheck %s
// RUN: %clang -### --target=armeb-none-eabi -fzero-call-used-regs=all -S %s 2>&1 | FileCheck %s
// RUN: %clang -### --target=thumbv7m-none-eabi -fzero-call-used-regs=all -S %s 2>&1 | FileCheck %s
// RUN: %clang -### --target=thumbv6m-none-eabi -fzero-call-used-regs=used -S %s 2>&1 | FileCheck %s

// CHECK-NOT: error: unsupported option
// CHECK: "-fzero-call-used-regs=

// Compile through each backend so accepting the flag also requires working
// register clearing. Keep the driver-only checks available in builds without ARM.
// RUN: %if arm-registered-target %{ %clang --target=arm-none-eabi -O2 \
// RUN:   -fzero-call-used-regs=all-gpr -S %s -o - | FileCheck %s --check-prefixes=ASM,ARM %}
// RUN: %if arm-registered-target %{ %clang --target=thumbv7m-none-eabi -O2 \
// RUN:   -fzero-call-used-regs=all-gpr -S %s -o - | FileCheck %s --check-prefixes=ASM,THUMB2 %}
// RUN: %if arm-registered-target %{ %clang --target=thumbv6m-none-eabi -O2 \
// RUN:   -fzero-call-used-regs=all-gpr -S %s -o - | FileCheck %s --check-prefixes=ASM,THUMB1 %}

// ASM-LABEL: clear_registers:
// ARM:         mov r1, #0
// ARM-NEXT:    mov r2, #0
// ARM-NEXT:    mov r3, #0
// ARM-NEXT:    mov r12, #0
// THUMB2:      movs r1, #0
// THUMB2-NEXT: movs r2, #0
// THUMB2-NEXT: movs r3, #0
// THUMB2-NEXT: mov.w r12, #0
// THUMB1:      movs r1, #0
// THUMB1-NEXT: mov r2, r1
// THUMB1-NEXT: mov r3, r1
// THUMB1-NEXT: mov r12, r1
// ASM-NEXT:    bx lr
int clear_registers(int x) { return x; }

// A target whose backend does not implement the clear is still refused, which
// is what keeps the check above from passing for the wrong reason.
// RUN: not %clang -### --target=powerpc64-unknown-linux-gnu -fzero-call-used-regs=all -S %s 2>&1 | \
// RUN:   FileCheck %s --check-prefix=REFUSED
// REFUSED: error: unsupported option '-fzero-call-used-regs=all' for target
