; RUN: llc -mtriple=armv7-none-eabi -verify-machineinstrs %s -o - | FileCheck %s
; RUN: llc -mtriple=thumbv6m-none-eabi -verify-machineinstrs %s -o - | FileCheck %s
; RUN: llc -mtriple=thumbv7m-none-eabi -verify-machineinstrs %s -o - | FileCheck %s

declare i32 @callee(i32)
define i32 @tail(i32 %x) "zeroize-flags" {
; CHECK-LABEL: tail:
; CHECK: bl callee
; CHECK: mov{{(s|w|\.w)?}} r1, #0
; CHECK: msr {{[Aa][Pp][Ss][Rr](_nzcvq)?}}, r1
; CHECK-NOT: bl
; CHECK: {{pop|bx}}
  %r = tail call i32 @callee(i32 %x)
  ret i32 %r
}
