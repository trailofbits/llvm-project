; RUN: llc -mtriple=armv7-none-eabi -mattr=+neon -verify-machineinstrs %s -o - | FileCheck %s --implicit-check-not='vmov.i32 q0'
; RUN: llc -mtriple=thumbv7-none-eabi -mattr=+neon -verify-machineinstrs %s -o - | FileCheck %s --implicit-check-not='vmov.i32 q0'
; RUN: llc -mtriple=armv7-none-eabi -mattr=+neon -filetype=obj %s -o /dev/null
; RUN: llc -mtriple=thumbv7-none-eabi -mattr=+neon -filetype=obj %s -o /dev/null

define arm_aapcs_vfpcc <4 x i32> @vector(<4 x i32> returned %x) "zeroize-flags" "zero-call-used-regs"="all" {
; CHECK-LABEL: vector:
; CHECK-DAG: vmov.i32 q1, #0x0
; CHECK-DAG: vmov.i32 q8, #0x0
; CHECK-DAG: vmov.i32 q15, #0x0
; CHECK: uadd8 r0, r0, r0
; CHECK-NEXT: msr APSR_nzcvq, r0
; CHECK-NEXT: bx lr
  ret <4 x i32> %x
}
