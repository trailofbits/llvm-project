; RUN: llc -mtriple=thumbv8.1m.main-none-eabi -mattr=+mve.fp -verify-machineinstrs %s -o - | FileCheck %s
; RUN: llc -mtriple=thumbv8.1m.main-none-eabi -mattr=+mve.fp -filetype=obj %s -o /dev/null
; RUN: llc -mtriple=thumbv8.1m.main-none-eabi -mattr=+mve -verify-machineinstrs %s -o - | FileCheck %s

define arm_aapcs_vfpcc <4 x i32> @vector(<4 x i32> returned %x) "zeroize-flags" "zero-call-used-regs"="all" {
; CHECK-LABEL: vector:
; CHECK-NOT: q0
; CHECK-DAG: vmov.i32 q1, #0x0
; CHECK-DAG: vmov.i32 q2, #0x0
; CHECK-DAG: vmov.i32 q3, #0x0
; CHECK-NOT: vmsr
; CHECK: vmsr vpr, r0
; CHECK-NEXT: msr apsr_nzcvqg, r0
; CHECK-NEXT: bx lr
  ret <4 x i32> %x
}

define void @flags_only() "zeroize-flags" {
; CHECK-LABEL: flags_only:
; CHECK: mov{{(s|w|\.w)?}} r0, #0
; CHECK-NEXT: vmsr vpr, r0
; CHECK-NEXT: msr apsr_nzcvqg, r0
; CHECK-NEXT: bx lr
  ret void
}
