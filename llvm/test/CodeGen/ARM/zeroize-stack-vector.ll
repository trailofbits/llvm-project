; RUN: llc -mtriple=armv7-none-eabihf -mattr=+neon -verify-machineinstrs %s -o - | FileCheck %s
; RUN: llc -mtriple=thumbv8.1m.main-none-eabihf -mattr=+mve.fp -verify-machineinstrs %s -o - | FileCheck %s
; RUN: llc -mtriple=armv7-none-eabihf -mattr=+neon -filetype=obj %s -o /dev/null
; RUN: llc -mtriple=thumbv8.1m.main-none-eabihf -mattr=+mve.fp -filetype=obj %s -o /dev/null

; Restore d8 before erasing its slot. Both the stack and register clears must
; preserve q0, which holds the vector result.
; CHECK-LABEL: vector_result:
; CHECK: vpush {d8}
; CHECK-NOT: {{vmov.*(q0|d0|d1|s0|s1|s2|s3),}}
; CHECK: vldr d8,
; CHECK-NOT: {{vmov.*(q0|d0|d1|s0|s1|s2|s3),}}
; CHECK: str
; CHECK: mov sp,
; CHECK-NOT: {{vmov.*(q0|d0|d1|s0|s1|s2|s3),}}
; CHECK: bx lr
define arm_aapcs_vfpcc <4 x i32> @vector_result(<4 x i32> %x) "zeroize-stack"="used" "zero-call-used-regs"="all" {
  %p = alloca [32 x i8], align 8
  store volatile i8 42, ptr %p
  call void asm sideeffect "", "~{d8}"()
  ret <4 x i32> %x
}
