; A clear is a definition nothing after it reads, which is what machine copy
; propagation and dead machine instruction elimination remove. The register
; clear marks what it cleared as read at the exit; this checks that both
; passes leave every clear in place and the return value intact.

; Thumb-1 copies one zero into the other registers, and copy propagation
; removes the copies once told to recognize target copies. The whole pipeline,
; with that option on.
; RUN: llc -mtriple=thumbv6m-none-eabi -mcp-use-is-copy-instr -verify-machineinstrs %s -o - \
; RUN:   | FileCheck %s --check-prefix=ASM

; The same pass, alone, on what prologue/epilogue insertion produced.
; RUN: llc -mtriple=thumbv6m-none-eabi -stop-after=prolog-epilog %s -o - \
; RUN:   | llc -mtriple=thumbv6m-none-eabi -x mir -run-pass=machine-cp -mcp-use-is-copy-instr -verify-machineinstrs -o - \
; RUN:   | FileCheck %s --check-prefix=THUMB1

; Elimination does not run after prologue/epilogue insertion by default, so it
; runs on its own here.
; RUN: llc -mtriple=thumbv6m-none-eabi -stop-after=prolog-epilog %s -o - \
; RUN:   | llc -mtriple=thumbv6m-none-eabi -x mir -run-pass=dead-mi-elimination -verify-machineinstrs -o - \
; RUN:   | FileCheck %s --check-prefix=THUMB1

; ARM clears with immediates, scalar and vector, so only elimination applies.
; RUN: llc -mtriple=armv7-none-eabi -stop-after=prolog-epilog %s -o - \
; RUN:   | llc -mtriple=armv7-none-eabi -x mir -run-pass=dead-mi-elimination -verify-machineinstrs -o - \
; RUN:   | FileCheck %s --check-prefix=ARM

; FP clearing can borrow a GPR that the requested mode does not select. Its
; zero must also remain live at the exit after its use by the FP clear.
; RUN: llc -mtriple=armv7-unknown-linux-gnueabihf -mattr=-neon -stop-after=prolog-epilog %s -o - \
; RUN:   | llc -mtriple=armv7-unknown-linux-gnueabihf -mattr=-neon -x mir -run-pass=dead-mi-elimination -verify-machineinstrs -o - \
; RUN:   | FileCheck %s --check-prefix=FP

; The return value stays in r0; the used arguments in r1 and r2 are cleared.
define i32 @used(i32 %a, i32 %b, i32 %c) "zero-call-used-regs"="used-gpr" {
; ASM-LABEL: used:
; ASM:         orrs r0, r2
; ASM-NEXT:    movs r1, #0
; ASM-NEXT:    mov r2, r1
; ASM-NEXT:    bx lr
;
; THUMB1-LABEL: name: used
; THUMB1:      = tORR
; THUMB1-NEXT: $r1, $cpsr = tMOVi8 0, 14 /* CC::al */, $noreg
; THUMB1-NEXT: $r2 = tMOVr $r1, 14 /* CC::al */, $noreg
; THUMB1-NEXT: tBX_RET 14 /* CC::al */, $noreg, implicit $r0, implicit $r1, implicit $r2
;
; ARM-LABEL: name: used
; ARM:      = ORRrr
; ARM-NEXT: $r1 = MOVi 0, 14 /* CC::al */, $noreg, $noreg
; ARM-NEXT: $r2 = MOVi 0, 14 /* CC::al */, $noreg, $noreg
; ARM-NEXT: BX_RET 14 /* CC::al */, $noreg, implicit $r0, implicit $r1, implicit $r2
  %x = mul i32 %a, %b
  %y = or i32 %x, %c
  ret i32 %y
}

; Every call-used register, including the high register and the vector ones.
define void @all() "zero-call-used-regs"="all" {
; ASM-LABEL: all:
; ASM:         movs r0, #0
; ASM-NEXT:    mov r1, r0
; ASM-NEXT:    mov r2, r0
; ASM-NEXT:    mov r3, r0
; ASM-NEXT:    mov r12, r0
; ASM-NEXT:    bx lr
;
; THUMB1-LABEL: name: all
; THUMB1:      $r0, $cpsr = tMOVi8 0, 14 /* CC::al */, $noreg
; THUMB1-NEXT: $r1 = tMOVr $r0, 14 /* CC::al */, $noreg
; THUMB1-NEXT: $r2 = tMOVr $r0, 14 /* CC::al */, $noreg
; THUMB1-NEXT: $r3 = tMOVr $r0, 14 /* CC::al */, $noreg
; THUMB1-NEXT: $r12 = tMOVr $r0, 14 /* CC::al */, $noreg
; THUMB1-NEXT: tBX_RET 14 /* CC::al */, $noreg, implicit $r0, implicit $r1, implicit $r2, implicit $r3, implicit $r12
;
; ARM-LABEL: name: all
; ARM:      $r0 = MOVi 0,
; ARM-NEXT: $r1 = MOVi 0,
; ARM-NEXT: $r2 = MOVi 0,
; ARM-NEXT: $r3 = MOVi 0,
; ARM-NEXT: $r12 = MOVi 0,
; ARM-NEXT: $q0 = VMOVv4i32 0,
; ARM-NEXT: $q1 = VMOVv4i32 0,
; ARM-NEXT: $q2 = VMOVv4i32 0,
; ARM-NEXT: $q3 = VMOVv4i32 0,
; ARM-NEXT: $q8 = VMOVv4i32 0,
; ARM-NEXT: $q9 = VMOVv4i32 0,
; ARM-NEXT: $q10 = VMOVv4i32 0,
; ARM-NEXT: $q11 = VMOVv4i32 0,
; ARM-NEXT: $q12 = VMOVv4i32 0,
; ARM-NEXT: $q13 = VMOVv4i32 0,
; ARM-NEXT: $q14 = VMOVv4i32 0,
; ARM-NEXT: $q15 = VMOVv4i32 0,
; ARM-NEXT: BX_RET 14 /* CC::al */, $noreg, implicit $r0, implicit $r1, implicit $r2, implicit $r3, implicit $r12, implicit $q0, implicit $q1, implicit $q2, implicit $q3, implicit $q8, implicit $q9, implicit $q10, implicit $q11, implicit $q12, implicit $q13, implicit $q14, implicit $q15
  ret void
}

; Only r12 was requested, but Thumb-1 also needs r0 as its zero source. Keep
; both allocatable defs live; the incidental CPSR def must not gain an exit use.
define void @scratch() "zero-call-used-regs"="used-gpr" {
; ASM-LABEL: scratch:
; ASM:         movs r0, #0
; ASM-NEXT:    mov r12, r0
; ASM-NEXT:    bx lr
;
; THUMB1-LABEL: name: scratch
; THUMB1:      $r0, $cpsr = tMOVi8 0, 14 /* CC::al */, $noreg
; THUMB1-NEXT: $r12 = tMOVr $r0, 14 /* CC::al */, $noreg
; THUMB1-NEXT: tBX_RET 14 /* CC::al */, $noreg, implicit $r0, implicit $r12{{$}}
;
; ARM-LABEL: name: scratch
; ARM:      $r12 = MOVi 0, 14 /* CC::al */, $noreg, $noreg
; ARM-NEXT: BX_RET 14 /* CC::al */, $noreg, implicit $r12{{$}}
  call void asm sideeffect "", "~{r12}"()
  ret void
}

define float @fp_scratch(float %a, float %b) "zero-call-used-regs"="used" {
; FP-LABEL: name: fp_scratch
; FP:      $r0 = MOVi 0, 14 /* CC::al */, $noreg, $noreg
; FP-NEXT: $s1 = VMOVSR $r0, 14 /* CC::al */, $noreg
; FP-NEXT: BX_RET 14 /* CC::al */, $noreg, implicit $s0, implicit $r0, implicit $s1{{$}}
  %r = fmul float %a, %b
  ret float %r
}
