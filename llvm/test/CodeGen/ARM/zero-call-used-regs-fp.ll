; What the floating-point half of the clear can use depends on the subtarget,
; and the four configurations here are the four answers: a vector immediate
; from NEON, a vector immediate from MVE, a move from a zeroed general-purpose
; register when there is neither, and nothing at all when the registers do not
; exist.

; RUN: llc -mtriple=armv7-unknown-linux-gnueabihf %s -o - | FileCheck %s --check-prefix=NEON
; RUN: llc -mtriple=thumbv8m.main -mattr=+fp-armv8d16sp %s -o - | FileCheck %s --check-prefix=VFP
; RUN: llc -mtriple=thumbv8.1m.main -mattr=+mve %s -o - | FileCheck %s --check-prefix=MVE
; RUN: llc -mtriple=thumbv7m-none-eabi %s -o - | FileCheck %s --check-prefix=NOFP

; D8-D15 are callee-saved, so the vector registers built out of them are the
; caller's and are not cleared: on NEON that leaves q0-q3 and q8-q15, and the
; gap where q4-q7 would be is the point. Every register in the gap is named,
; not a sample of it. Clearing one of these is an ABI violation, and a guard
; that covers some of a set is one a violation can walk between.
; NEON-LABEL: all_regs:
; NEON:         vmov.i32 q0, #0x0
; NEON-NEXT:    mov r0, #0
; NEON:         vmov.i32 q3, #0x0
; NEON-NOT:     vmov.i32 q4,
; NEON-NOT:     vmov.i32 q5,
; NEON-NOT:     vmov.i32 q6,
; NEON-NOT:     vmov.i32 q7,
; NEON:         vmov.i32 q8, #0x0
; NEON:         vmov.i32 q15, #0x0
; NEON-NEXT:    bx lr
;
; With floating-point registers but no vector immediate, each register is
; written from one that has been zeroed already. A d register takes two halves
; of it, which is the same instruction the security extension's own clearing
; sequence uses.
; VFP-LABEL: all_regs:
; VFP:         movs r0, #0
; VFP:         vmov d0, r0, r0
; VFP:         vmov d7, r0, r0
; VFP-NOT:     vmov d8,
; VFP-NOT:     vmov d9,
; VFP-NOT:     vmov d10,
; VFP-NOT:     vmov d11,
; VFP-NOT:     vmov d12,
; VFP-NOT:     vmov d13,
; VFP-NOT:     vmov d14,
; VFP-NOT:     vmov d15,
; VFP:         bx lr
;
; MVE reaches q0-q7 and, unlike NEON, has a predicate register that is neither
; general-purpose nor part of the vector file. It is data, so it is cleared.
; MVE-LABEL: all_regs:
; MVE:         movs r0, #0
; MVE:         vmov.i32 q0, #0x0
; MVE:         vmov.i32 q3, #0x0
; MVE-NEXT:    vmsr vpr, r0
; MVE-NEXT:    bx lr
;
; Without floating-point registers there is nothing in them to destroy, because
; no instruction exists that could have put anything there.
; NOFP-LABEL: all_regs:
; NOFP:         movs r0, #0
; NOFP:         mov.w r12, #0
; NOFP-NEXT:    bx lr
; NOFP-NOT:     vmov
define void @all_regs() "zero-call-used-regs"="all" {
  ret void
}

; s0 is the return value and s1 is not, and they are the two halves of d0. The
; wider register cannot stand in for the half that was asked for: clearing d0
; here would destroy the value being returned. So the clear stays at the width
; it was asked for, and pays for a zeroed general-purpose register to do it.
; NEON-LABEL: half_a_pair:
; NEON:         vmul.f32 s0, s0, s1
; NEON-NEXT:    mov r0, #0
; NEON-NEXT:    vmov s1, r0
; NEON-NEXT:    bx lr
; NEON-NOT:     vmov.i32 d0
define float @half_a_pair(float %a, float %b) noinline optnone "zero-call-used-regs"="used" {
  %r = fmul float %a, %b
  ret float %r
}
