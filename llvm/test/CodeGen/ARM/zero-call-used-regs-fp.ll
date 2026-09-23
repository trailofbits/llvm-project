; What the floating-point half of the clear can use depends on the subtarget,
; and the configurations here cover the four answers: a vector immediate
; from NEON, a vector immediate from MVE, a move from a zeroed general-purpose
; register when there is neither, and nothing at all when the registers are
; unavailable in the current instruction set.

; RUN: llc -mtriple=armv7-unknown-linux-gnueabihf %s -o %t.neon.s
; RUN: FileCheck %s --check-prefix=NEON < %t.neon.s
; RUN: FileCheck %s --check-prefix=NEON-GAP < %t.neon.s
; RUN: llc -mtriple=thumbv8m.main -mattr=+fp-armv8d16sp %s -o - | FileCheck %s --check-prefix=VFP
; RUN: llc -mtriple=thumbv8.1m.main -mattr=+mve %s -o - | FileCheck %s --check-prefix=MVE
; RUN: llc -mtriple=thumbv7m-none-eabi %s -o - | FileCheck %s --check-prefix=NOFP
; RUN: llc -mtriple=thumbv6-none-eabi -mattr=+vfp2 -verify-machineinstrs %s -o - | FileCheck %s --check-prefix=THUMB1 --implicit-check-not=vmov
; RUN: llc -mtriple=thumbv6-none-eabi -mcpu=arm1176jzf-s -verify-machineinstrs %s -o - | FileCheck %s --check-prefix=THUMB1 --implicit-check-not=vmov
; RUN: llc -mtriple=armv6-none-eabi -mattr=+vfp2 -verify-machineinstrs %s -o - | FileCheck %s --check-prefix=VFP
; RUN: llc -mtriple=thumbv6t2-none-eabi -mattr=+vfp2 -verify-machineinstrs %s -o - | FileCheck %s --check-prefix=VFP

; D8-D15 are callee-saved, so the vector registers built out of them are the
; caller's and are not cleared: on NEON that leaves q0-q3 and q8-q15, and the
; gap where q4-q7 would be is the point. The scheduler may interleave the
; general-purpose and vector clears, so the set is pinned and the order is
; not. The gap is checked in a second pass, since a NOT cannot see inside a
; DAG block.
; NEON-GAP-LABEL: all_regs:
; NEON-GAP-NOT:   vmov.i32 q{{[4-7]}},
; NEON-GAP:       bx lr
;
; NEON-LABEL: all_regs:
; NEON-DAG:     mov r0, #0
; NEON-DAG:     mov r12, #0
; NEON-DAG:     vmov.i32 q0, #0x0
; NEON-DAG:     vmov.i32 q1, #0x0
; NEON-DAG:     vmov.i32 q2, #0x0
; NEON-DAG:     vmov.i32 q3, #0x0
; NEON-DAG:     vmov.i32 q8, #0x0
; NEON-DAG:     vmov.i32 q9, #0x0
; NEON-DAG:     vmov.i32 q10, #0x0
; NEON-DAG:     vmov.i32 q11, #0x0
; NEON-DAG:     vmov.i32 q12, #0x0
; NEON-DAG:     vmov.i32 q13, #0x0
; NEON-DAG:     vmov.i32 q14, #0x0
; NEON-DAG:     vmov.i32 q15, #0x0
; NEON:         bx lr
;
; With floating-point registers but no vector immediate, each register is
; written from one that has been zeroed already. A d register takes two halves
; of it, which is the same instruction the security extension's own clearing
; sequence uses.
; VFP-LABEL: all_regs:
; VFP:         mov{{s?}} r0, #0
; VFP:         vmov d0, r0, r0
; VFP:         vmov d7, r0, r0
; VFP-NEXT:    bx lr
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
;
; Thumb-1 cannot access VFP registers even when the CPU has them. Only the
; general-purpose registers are cleared; ARM and Thumb-2 still clear VFP.
; THUMB1-LABEL: all_regs:
; THUMB1:         movs r0, #0
; THUMB1-NEXT:    mov r1, r0
; THUMB1-NEXT:    mov r2, r0
; THUMB1-NEXT:    mov r3, r0
; THUMB1-NEXT:    mov r12, r0
; THUMB1-NEXT:    bx lr
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
