; RUN: llc -mtriple=aarch64-unknown-linux-gnu -verify-machineinstrs %s -o - | FileCheck %s
; RUN: llc -mtriple=aarch64-unknown-linux-gnu -O0 -verify-machineinstrs %s -o - | FileCheck %s
; RUN: llc -mtriple=aarch64-unknown-linux-gnu -enable-post-misched -verify-machineinstrs %s -o - \
; RUN: | FileCheck %s
; RUN: llc -mtriple=aarch64-unknown-linux-gnu -filetype=obj %s -o /dev/null

; CHECK-LABEL: flags_only:
; CHECK: add w0, w0, #1
; CHECK: msr NZCV, xzr
; CHECK-NEXT: ret
define i32 @flags_only(i32 %x) "zeroize-flags" {
  %r = add i32 %x, 1
  ret i32 %r
}

; CHECK-LABEL: flags_and_registers:
; CHECK: mov x1, #0
; CHECK: msr NZCV, xzr
; CHECK-NEXT: ret
define i64 @flags_and_registers(i64 %x) "zeroize-flags" "zero-call-used-regs"="all-gpr" {
  ret i64 %x
}

; CHECK-LABEL: unprotected:
; CHECK-NOT: msr
; CHECK: ret
define i64 @unprotected(i64 %x) {
  ret i64 %x
}
