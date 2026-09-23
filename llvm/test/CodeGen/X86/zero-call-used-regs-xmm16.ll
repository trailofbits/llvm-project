; XMM16-31 have only EVEX encodings, and "used" can request one alone, without
; its YMM or ZMM register. The clear is the 128-bit form with VLX and the
; 512-bit form without; both zero the whole register.

; RUN: llc < %s -mtriple=x86_64-unknown-linux-gnu -mattr=+avx512f -verify-machineinstrs | FileCheck --check-prefix=F %s
; RUN: llc < %s -mtriple=x86_64-unknown-linux-gnu -mattr=+avx512f,+avx512vl -verify-machineinstrs | FileCheck --check-prefix=VL %s
; RUN: llc < %s -mtriple=x86_64-unknown-linux-gnu -mattr=+avx512f -verify-machineinstrs -o /dev/null 2>&1 | count 0

define void @used_xmm16(<4 x float> %v) "zero-call-used-regs"="used" {
; F-LABEL: used_xmm16:
; F:         vpxord %zmm16, %zmm16, %zmm16
; F-NOT:     xmm16
; F:         retq
;
; VL-LABEL: used_xmm16:
; VL:         vpxord %xmm16, %xmm16, %xmm16
; VL-NOT:     zmm16
; VL:         retq
  call void asm sideeffect "", "{xmm16}"(<4 x float> %v)
  ret void
}
