; RUN: llc -mtriple=armv7-none-eabihf -mattr=+neon -verify-machineinstrs %s -o - | FileCheck %s
; RUN: llc -mtriple=thumbv8.1m.main-none-eabihf -mattr=+mve -verify-machineinstrs %s -o - | FileCheck %s
; RUN: llc -mtriple=thumbv8.1m.main-none-eabihf -mattr=+mve.fp -verify-machineinstrs %s -o - | FileCheck %s
; RUN: llc -mtriple=armv7-none-eabihf -mattr=+neon -filetype=obj %s -o /dev/null
; RUN: llc -mtriple=thumbv8.1m.main-none-eabihf -mattr=+mve -filetype=obj %s -o /dev/null

; A tuple may overlap q0 without being its subregister or superregister.
; Expanding such a candidate must not reintroduce live return-value leaves.
; CHECK-LABEL: vector_result:
; CHECK-NOT: {{vmov.*(q0|d0|d1|s0|s1|s2|s3),}}
; CHECK: vmov.i32 q1, #0x0
; CHECK-NOT: {{vmov.*(q0|d0|d1|s0|s1|s2|s3),}}
; CHECK: bx lr
define arm_aapcs_vfpcc <4 x i32> @vector_result(<4 x i32> %x) "zero-call-used-regs"="all" {
  ret <4 x i32> %x
}
