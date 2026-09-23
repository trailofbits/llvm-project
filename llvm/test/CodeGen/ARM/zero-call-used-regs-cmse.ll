; RUN: llc -mtriple=thumbv8m.base-none-eabi -mattr=+8msecext -verify-machineinstrs %s -o - | FileCheck %s --check-prefixes=CHECK,BASE
; RUN: llc -mtriple=thumbv8m.main-none-eabi -mattr=+8msecext,-fpregs -verify-machineinstrs %s -o - | FileCheck %s --check-prefixes=CHECK,MAIN
; RUN: llc -mtriple=thumbv8m.main-none-eabi -mattr=+8msecext,+fp-armv8d16sp -verify-machineinstrs %s -o - | FileCheck %s --check-prefixes=CHECK,MAIN,FP
; RUN: llc -mtriple=thumbv8.1m.main-none-eabi -mattr=+8msecext -verify-machineinstrs %s -o - | FileCheck %s --check-prefixes=CHECK,V81
; RUN: llc -mtriple=thumbv8m.main-none-eabi -mattr=+8msecext,+fp-armv8d16sp -mcp-use-is-copy-instr -verify-machineinstrs %s -o - | FileCheck %s --check-prefixes=CHECK,MAIN,FP

; PEI adds implicit uses to retain the clears. R12 cannot hold a return value,
; but the CMSE return expansion uses it for CONTROL/FPSCR and authentication.
; It must accept that implicit use and leave R12 zero after its own writes.
define i32 @all_gpr(i32 %x) "cmse_nonsecure_entry" "zero-call-used-regs"="all-gpr" {
; CHECK-LABEL: all_gpr:
; FP:          mrs r12, control
; FP:          vmsr{{(ne)?}} fpscr, r12
; BASE:        movw r12, #0
; MAIN:        mov.w r12, #0
; V81:         clrm {r12, apsr}
; CHECK-NOT:   mov r12, lr
; CHECK-NOT:   {{mov.*}} r0,
; CHECK:       bxns lr
  ret i32 %x
}

; Cover FP clearing requests as well as GPRs.
define i32 @all_regs(i32 %x) "cmse_nonsecure_entry" "zero-call-used-regs"="all" {
; CHECK-LABEL: all_regs:
; FP:          mrs r12, control
; FP:          vmsr{{(ne)?}} fpscr, r12
; BASE:        movw r12, #0
; MAIN:        mov.w r12, #0
; V81:         clrm {r12, apsr}
; CHECK-NOT:   mov r12, lr
; CHECK-NOT:   {{mov.*}} r0,
; CHECK:       bxns lr
  ret i32 %x
}

; An individual used-register request must be honored too. Minsize avoids the
; CONTROL branch in the floating-point clearing expansion.
define i32 @used_r12(i32 %x) minsize "cmse_nonsecure_entry" "zero-call-used-regs"="used-gpr" {
; CHECK-LABEL: used_r12:
; FP:          vmsr{{(ne)?}} fpscr, r12
; BASE:        movw r12, #0
; MAIN:        mov.w r12, #0
; V81:         clrm {r1, r2, r3, r12, apsr}
; CHECK-NOT:   mov r12, lr
; CHECK-NOT:   {{mov.*}} r0,
; CHECK:       bxns lr
  call void asm sideeffect "", "~{r12}"()
  ret i32 %x
}

; With no zeroing request, retain the ordinary CMSE clearing sequence.
define i32 @skip(i32 %x) "cmse_nonsecure_entry" "zero-call-used-regs"="skip" {
; CHECK-LABEL: skip:
; BASE:        mov r12, lr
; MAIN:        mov r12, lr
; V81:         clrm {r1, r2, r3, r12, apsr}
; CHECK:       bxns lr
  ret i32 %x
}
