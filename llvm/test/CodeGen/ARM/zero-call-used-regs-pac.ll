; RUN: llc -mtriple=thumbv8m.main-none-eabi -mattr=+8msecext,+pacbti,+fp-armv8d16sp -verify-machineinstrs %s -o - | FileCheck %s --check-prefixes=CHECK,V8
; RUN: llc -mtriple=thumbv8.1m.main-none-eabi -mattr=+8msecext,+pacbti -verify-machineinstrs %s -o - | FileCheck %s --check-prefixes=CHECK,V81

; An ordinary v8.1-M return authenticates in BXAUT. Its implicit R12 operand
; must preserve the authentication code through register clearing. On v8-M,
; a separate AUT runs before the clears, so R12 can be cleared afterwards.
define i32 @signed_return(i32 %x) "sign-return-address"="all" "zero-call-used-regs"="all-gpr" {
; CHECK-LABEL: signed_return:
; CHECK:         pac r12, lr, sp
; CHECK:         str r12, [sp, #-4]!
; CHECK:         ldr r12, [sp], #4
; V8-NEXT:       aut r12, lr, sp
; CHECK-NEXT:    movs r1, #0
; CHECK-NEXT:    movs r2, #0
; CHECK-NEXT:    movs r3, #0
; V8:            mov.w r12, #0
; V8-NEXT:       bx lr
; V81-NOT:       {{mov.*}} r12,
; V81-NEXT:      bxaut r12, lr, sp
  ret i32 %x
}

; R12 holds the return-address authentication code until AUT. Register
; clearing must preserve it until then and clear it before leaving the secure
; state.
define i32 @signed_cmse_return(i32 %x) "cmse_nonsecure_entry" "sign-return-address"="all" "zero-call-used-regs"="all-gpr" {
; CHECK-LABEL: signed_cmse_return:
; CHECK:         pac r12, lr, sp
; CHECK:         str r12, [sp, #-4]!
; CHECK:         ldr r12, [sp], #4
; CHECK-NOT:     {{mov.*}} r12, #0
; V8-NEXT:       aut r12, lr, sp
; V8:            mrs r12, control
; V8:            vmsr fpscr, r12
; V8-NEXT:       mov.w r12, #0
; V8:          {{^}}.LBB{{[0-9_]+}}:
; V8-NEXT:       mov.w r12, #0
; V8-NEXT:       mov r1, r12
; V8-NEXT:       mov r2, r12
; V8-NEXT:       mov r3, r12
; V8-NEXT:       msr apsr_nzcvq, r12
; V8-NEXT:       bxns lr
; V81:           aut r12, lr, sp
; V81-NEXT:      clrm {r1, r2, r3, r12, apsr}
; V81-NEXT:      bxns lr
  ret i32 %x
}
