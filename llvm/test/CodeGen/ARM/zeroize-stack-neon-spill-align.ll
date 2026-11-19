; RUN: llc -mtriple=armv7-unknown-linux-gnueabihf -mattr=+neon -O2 -verify-machineinstrs %s -o - | FileCheck %s --check-prefix=ASM
; RUN: llc -mtriple=armv7-unknown-linux-gnueabihf -mattr=+neon -O2 -stop-before=prolog-epilog %s -o - | FileCheck %s --check-prefix=MIR
; RUN: sed 's/"zeroize-stack"="used"//' %s | llc -mtriple=armv7-unknown-linux-gnueabihf -mattr=+neon -O2 -stop-before=prolog-epilog -o - | FileCheck %s --check-prefix=CONTROL

; A vector live across the clobber must spill. Retaining the frame pointer
; permits optional realignment, but an ABI-aligned slot suffices for the spill.
; MIR: type: spill-slot, offset: 0, size: 16, alignment: 8,
; MIR: (store (s128) into %stack.[[SLOT:[0-9]+]], align 8)
; MIR: (load (s128) from %stack.[[SLOT]], align 8)
; CONTROL: type: spill-slot, offset: 0, size: 16, alignment: 16,
; ASM-LABEL: protected_spill:
; ASM: vstmia
; ASM: vldmia
; ASM: mov [[ZERO:r[0-9]+]], #0
; ASM: str [[ZERO]], [
; ASM: bx lr
define <4 x i32> @protected_spill(<4 x i32> %v) "frame-pointer"="all" "zeroize-stack"="used" {
  %value = call <4 x i32> asm sideeffect "", "=w,0"(<4 x i32> %v)
  call void asm sideeffect "", "~{q0},~{q1},~{q2},~{q3},~{q4},~{q5},~{q6},~{q7},~{q8},~{q9},~{q10},~{q11},~{q12},~{q13},~{q14},~{q15}"()
  %result = call <4 x i32> asm sideeffect "", "=w,0"(<4 x i32> %value)
  ret <4 x i32> %result
}
