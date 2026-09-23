; Non-M-class interrupt handlers share FP state with the interrupted code.
; Omitting FP registers from the CSR list does not make them safe to clear.
; Check both immediate vector clears and clears that would need a spare GPR.
;
; RUN: llc -mtriple=armv7a-none-eabi -mattr=+neon -verify-machineinstrs %s -o - | FileCheck %s --check-prefix=AR --implicit-check-not=vmov
; RUN: llc -mtriple=thumbv7a-none-eabi -mattr=+neon -verify-machineinstrs %s -o - | FileCheck %s --check-prefix=AR --implicit-check-not=vmov
; RUN: llc -mtriple=armv7a-none-eabi -mattr=+vfp3,-neon -verify-machineinstrs %s -o - | FileCheck %s --check-prefix=AR --implicit-check-not=vmov
; RUN: llc -mtriple=armv8r-none-eabi -mcpu=cortex-r52 -verify-machineinstrs %s -o - | FileCheck %s --check-prefix=AR --implicit-check-not=vmov
; RUN: llc -mtriple=armv7r-none-eabi -mcpu=cortex-r5 -verify-machineinstrs %s -o - | FileCheck %s --check-prefix=AR --implicit-check-not=vmov
; RUN: llc -mtriple=thumbv7em-none-eabi -mcpu=cortex-m4 -verify-machineinstrs %s -o - | FileCheck %s --check-prefix=M

define void @irq_all() "interrupt"="IRQ" "zero-call-used-regs"="all" {
; AR-LABEL: irq_all:
; AR:         subs pc, lr, #4
;
; M-class handlers use AAPCS register preservation and can clear call-used FP
; registers. Do not apply the non-M-class restriction here.
; M-LABEL: irq_all:
; M:         movs r0, #0
; M:         vmov d0, r0, r0
; M:         vmov d7, r0, r0
; M:         bx lr
  ret void
}

; Selecting just S0 requires a zero source. In an IRQ handler all GPRs are
; callee-saved, so attempting this clear used to fail with no free register.
define void @irq_used() "interrupt"="IRQ" "zero-call-used-regs"="used" {
; AR-LABEL: irq_used:
; AR:         subs pc, lr, #4
;
; M-LABEL: irq_used:
; M:         movs r0, #0
; M-NEXT:    vmov s0, r0
; M-NEXT:    bx lr
  call void asm sideeffect "", "~{s0}"()
  ret void
}

; save-fp preserves the interrupted context; it does not authorize clearing
; that context after the epilogue has restored it.
define void @irq_all_save_fp() "interrupt"="IRQ" "save-fp" "zero-call-used-regs"="all" {
; AR-LABEL: irq_all_save_fp:
; AR:         subs pc, lr, #4
  ret void
}

define void @irq_used_save_fp() "interrupt"="IRQ" "save-fp" "zero-call-used-regs"="used" {
; AR-LABEL: irq_used_save_fp:
; AR:         vpush {d0}
; AR:         vpop {d0}
; AR:         subs pc, lr, #4
  call void asm sideeffect "", "~{s0}"()
  ret void
}

; FIQ has banked GPRs which are still eligible for clearing. R11 remains
; callee-saved because frame lowering may use it as the frame pointer.
define void @fiq_all() "interrupt"="FIQ" "zero-call-used-regs"="all" {
; AR-LABEL: fiq_all:
; AR-DAG:     mov{{(\.w)?}} r8, #0
; AR-DAG:     mov{{(\.w)?}} r9, #0
; AR-DAG:     mov{{(\.w)?}} r10, #0
; AR-DAG:     mov{{(\.w)?}} r12, #0
; AR:         subs pc, lr, #4
  ret void
}

define void @fiq_all_save_fp() "interrupt"="FIQ" "save-fp" "zero-call-used-regs"="all" {
; AR-LABEL: fiq_all_save_fp:
; AR-DAG:     mov{{(\.w)?}} r8, #0
; AR-DAG:     mov{{(\.w)?}} r9, #0
; AR-DAG:     mov{{(\.w)?}} r10, #0
; AR-DAG:     mov{{(\.w)?}} r12, #0
; AR:         subs pc, lr, #4
  ret void
}
