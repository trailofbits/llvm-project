; RUN: llc -mtriple=thumbv8m.main-none-eabi -mattr=+8msecext,+pacbti,+fp-armv8d16sp -verify-machineinstrs %s -o - | FileCheck %s --check-prefixes=CHECK,V8
; RUN: llc -mtriple=thumbv8.1m.main-none-eabi -mattr=+8msecext,+pacbti -verify-machineinstrs %s -o - | FileCheck %s --check-prefixes=CHECK,V81

; R12 holds the return-address authentication code until AUT. Register
; clearing must preserve it until then and clear it before leaving the secure
; state.
define i32 @signed_return(i32 %x) "cmse_nonsecure_entry" "sign-return-address"="all" "zero-call-used-regs"="all-gpr" {
; CHECK-LABEL: signed_return:
; CHECK:         pac r12, lr, sp
; CHECK:         str r12, [sp, #-4]!
; CHECK:         ldr r12, [sp], #4
; CHECK-NOT:     {{mov.*}} r12, #0
; V8-NEXT:       aut r12, lr, sp
; V8:            mrs r12, control
; V8:            vmsr fpscr, r12
; V8:            mov.w r12, #0
; V8-NEXT:       msr apsr_nzcvq, lr
; V8-NEXT:       bxns lr
; V81:           aut r12, lr, sp
; V81-NEXT:      clrm {r12, apsr}
; V81-NEXT:      bxns lr
  ret i32 %x
}
