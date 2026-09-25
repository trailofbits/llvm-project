; RUN: llc -mtriple=aarch64-unknown-linux-gnu -O2 -verify-machineinstrs < %s | FileCheck %s

define i64 @dirty_undef() "zero-call-used-regs"="used-gpr" {
; CHECK-LABEL: dirty_undef:
; CHECK: mov x0, #123
; CHECK: mov x0, #0
; CHECK-NEXT: ret
  call void asm sideeffect "mov x0, #123", "~{x0}"()
  ret i64 undef
}

define i64 @dirty_live() "zero-call-used-regs"="used-gpr" {
; CHECK-LABEL: dirty_live:
; CHECK: mov x0, #123
; CHECK-NOT: mov x0, #0
; CHECK: ret
  %value = call i64 asm sideeffect "mov x0, #123", "={x0}"()
  ret i64 %value
}
