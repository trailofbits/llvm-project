; RUN: llc -mtriple=armv7-none-eabihf -mattr=+neon -verify-machineinstrs %s -o - | FileCheck %s --check-prefixes=CHECK,NEON
; RUN: llc -mtriple=armv7-none-eabihf -mattr=+vfp2,-neon -verify-machineinstrs %s -o - | FileCheck %s --check-prefixes=CHECK,VFP
; RUN: llc -mtriple=thumbv8m.main-none-eabihf -mattr=+fp-armv8d16sp -verify-machineinstrs %s -o - | FileCheck %s --check-prefixes=CHECK,VFP
; RUN: llc -mtriple=thumbv8.1m.main-none-eabihf -mattr=+mve.fp -verify-machineinstrs %s -o - | FileCheck %s --check-prefixes=CHECK,MVE
; RUN: llc -mtriple=armv7-none-eabihf -mattr=+neon -filetype=obj %s -o /dev/null
; RUN: llc -mtriple=armv7-none-eabihf -mattr=+vfp3,-neon -filetype=obj %s -o /dev/null
; RUN: llc -mtriple=thumbv8m.main-none-eabihf -mattr=+fp-armv8d16sp -filetype=obj %s -o /dev/null
; RUN: llc -mtriple=thumbv8.1m.main-none-eabihf -mattr=+mve.fp -filetype=obj %s -o /dev/null

; The unselected half of d0 is a return value. Clearing s1 must not widen to
; d0 or q0, even though vector immediate instructions would be cheaper.
; CHECK-LABEL: float_result:
; CHECK: mov{{.*}} r0, #0
; CHECK-NOT: {{vmov.*(s0|d0|q0),}}
; CHECK: vmov s1, r0
; CHECK-NOT: {{vmov.*(s0|d0|q0),}}
; CHECK: bx lr
define arm_aapcs_vfpcc float @float_result(float %x) "zero-call-used-regs"="all-arg" {
  ret float %x
}

; With a whole d0 return value, d1 is still clearable but q0 is not.
; CHECK-LABEL: double_result:
; CHECK-NOT: {{vmov.*(s0|s1|d0|q0),}}
; NEON: vmov.i32 d1, #0x0
; VFP: vmov d1, r0, r0
; MVE: vmov d1, r0, r0
; CHECK-NOT: {{vmov.*(s0|s1|d0|q0),}}
; CHECK: bx lr
define arm_aapcs_vfpcc double @double_result(double %x) "zero-call-used-regs"="all" {
  ret double %x
}
