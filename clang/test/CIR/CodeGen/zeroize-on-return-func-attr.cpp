// RUN: %clang_cc1 -triple x86_64-unknown-linux-gnu -fclangir -emit-cir %s -o %t.cir
// RUN: FileCheck --input-file=%t.cir %s -check-prefix=CIR
// RUN: %clang_cc1 -triple x86_64-unknown-linux-gnu -fclangir -emit-llvm %s -o %t.ll
// RUN: FileCheck --input-file=%t.ll %s -check-prefix=LLVM
// RUN: %clang_cc1 -triple x86_64-unknown-linux-gnu -emit-llvm %s -o %t.ll
// RUN: FileCheck --input-file=%t.ll %s -check-prefix=LLVM

// RUN: %clang_cc1 -triple x86_64-unknown-linux-gnu -fzero-call-used-regs=skip -fclangir -emit-cir %s -o %t.cir
// RUN: FileCheck --input-file=%t.cir %s -check-prefix=CIR
// RUN: %clang_cc1 -triple x86_64-unknown-linux-gnu -fzero-call-used-regs=skip -fclangir -emit-llvm %s -o %t.ll
// RUN: FileCheck --input-file=%t.ll %s -check-prefix=LLVM
// RUN: %clang_cc1 -triple x86_64-unknown-linux-gnu -fzero-call-used-regs=skip -emit-llvm %s -o %t.ll
// RUN: FileCheck --input-file=%t.ll %s -check-prefix=LLVM

// The same prefix is used for every mode on purpose: a protected function
// emits the same two requests whatever the command line says. The third RUN
// of each group is classic codegen, which pins ClangIR to parity with it.

extern "C" {
  [[clang::zeroize_on_return]]
  void protected_fn() {}
  // CIR: cir.func{{.*}}@protected_fn()
  // CIR-SAME: zero_call_used_regs = "all"
  // CIR-SAME: zeroize_stack = "used"
  // LLVM: define{{.*}}@protected_fn() #[[PROT_ATTR:.*]] {

  void plain_fn() {}
  // CIR: cir.func{{.*}}@plain_fn()
  // CIR-NOT: zeroize_stack
  // LLVM: define{{.*}}@plain_fn() #[[PLAIN_ATTR:.*]] {

  void caller() {
    protected_fn();
    // The request is a property of the function, not of calls to it.
    // CIR: cir.call{{.*}}@protected_fn()
    // CIR-NOT: zeroize_stack
    // LLVM: call void{{.*}}@protected_fn(){{$}}
  }
}

// LLVM: attributes #[[PROT_ATTR]]
// LLVM-SAME: "zero-call-used-regs"="all"
// LLVM-SAME: "zeroize-stack"="used"
// LLVM: attributes #[[PLAIN_ATTR]]
// LLVM-NOT: "zeroize-stack"
