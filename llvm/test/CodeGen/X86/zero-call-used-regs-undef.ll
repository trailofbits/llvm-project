; RUN: llc -mtriple=x86_64-unknown-linux-gnu -O2 -verify-machineinstrs < %s | FileCheck %s

; At -O2, this undef return lowers to an undef machine-register use.
; IR undef returns that lower to ordinary uses (e.g. at -O0) still exclude the
; corresponding registers from clearing.
define i64 @dirty_undef() "zero-call-used-regs"="used-gpr" {
; CHECK-LABEL: dirty_undef:
; CHECK: movq $123, %rax
; CHECK: xorl %eax, %eax
; CHECK-NEXT: retq
  call void asm sideeffect "movq $$123, %rax", "~{rax}"()
  ret i64 undef
}

define i64 @dirty_live() "zero-call-used-regs"="used-gpr" {
; CHECK-LABEL: dirty_live:
; CHECK: movq $123, %rax
; CHECK-NOT: xorl %eax, %eax
; CHECK: retq
  %value = call i64 asm sideeffect "movq $$123, %rax", "={rax}"()
  ret i64 %value
}
