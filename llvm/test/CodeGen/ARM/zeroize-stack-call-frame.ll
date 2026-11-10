; RUN: llc -mtriple=armv7-none-eabi -verify-machineinstrs %s -o - | FileCheck %s
; RUN: llc -mtriple=thumbv6m-none-eabi -verify-machineinstrs %s -o - | FileCheck %s
; RUN: llc -mtriple=thumbv7m-none-eabi -verify-machineinstrs %s -o - | FileCheck %s

; Outgoing arguments larger than Thumb's usual reservation threshold must
; remain in the owned frame until they have been erased.
; CHECK-LABEL: outgoing:
; CHECK: bl many
; CHECK-NOT: add sp,
; CHECK-NOT: add.w sp,
; CHECK: str r1, [r0]
; CHECK: cmp r0, r12
; CHECK: bne
; CHECK: mov sp, r0
; CHECK: bx lr
declare void @many(ptr byval([600 x i8]) align 4)
define void @outgoing(ptr %p) "zeroize-stack"="used" {
  call void @many(ptr byval([600 x i8]) align 4 %p)
  ret void
}

; An otherwise eligible tail call must leave a clearing epilogue behind.
; CHECK-LABEL: tail_request:
; CHECK: bl callee
; CHECK: str r2, [r1]
; CHECK: mov sp, r1
; CHECK: bx lr
declare i32 @callee(i32)
define i32 @tail_request(i32 %x) "zeroize-stack"="used" {
  %v = tail call i32 @callee(i32 %x)
  ret i32 %v
}
