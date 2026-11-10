; RUN: llc -mtriple=armv4t-none-eabi -verify-machineinstrs %s -o - | FileCheck %s
; RUN: llc -mtriple=armv5te-none-eabi -verify-machineinstrs %s -o - | FileCheck %s
; RUN: llc -mtriple=armv5te-none-eabi -filetype=obj %s -o /dev/null

define i32 @pre_ge(i32 returned %x) "zeroize-flags" {
; CHECK-LABEL: pre_ge:
; CHECK: mov r1, #0
; CHECK-NEXT: msr APSR_nzcvq, r1
; CHECK-NEXT: bx lr
  ret i32 %x
}
