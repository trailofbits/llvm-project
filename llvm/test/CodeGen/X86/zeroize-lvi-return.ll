; RUN: llc -mtriple=x86_64-linux-gnu -mattr=+sahf,+lvi-cfi -verify-machineinstrs -O0 %s -o - | FileCheck %s
; RUN: llc -mtriple=x86_64-linux-gnu -mattr=+sahf,+lvi-cfi,+lvi-load-hardening -verify-machineinstrs -O2 %s -o - | FileCheck %s

; The popped value is the full incoming address. A live RAX result forces a
; different scratch register. RSP already points at the incoming return slot.
define i64 @preserved(i64 %x) #0 {
; CHECK-LABEL: preserved:
; CHECK: mov{{[ql]}} $0, {{.*}}(%rsp)
; CHECK: sahf
; CHECK-NEXT: xchgq %r11, %rax
; CHECK-NEXT: {{.*}}fake_use
; CHECK-NEXT: popq %rcx
; CHECK: .cfi_def_cfa %rsp, 0
; CHECK-NEXT: .cfi_register %rip, %rcx
; CHECK-NEXT: lfence
; CHECK-NEXT: jmpq *%rcx
  %slot = alloca i64
  store volatile i64 %x, ptr %slot
  %y = load volatile i64, ptr %slot
  ret i64 %y
}

define void @no_result() #0 {
; CHECK-LABEL: no_result:
; CHECK: sahf
; CHECK-NEXT: {{.*}}fake_use
; CHECK-NEXT: popq %rax
; CHECK: lfence
; CHECK-NEXT: jmpq *%rax
  ret void
}

attributes #0 = { uwtable "zero-call-used-regs"="all" "zeroize-flags" "zeroize-stack"="used" }
