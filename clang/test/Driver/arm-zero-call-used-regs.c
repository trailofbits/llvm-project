// The backend clears the call-used registers on 32-bit Arm, in each of its
// three instruction-set modes, so the driver no longer refuses the request.

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
