; The upper D registers must be preserved by save-fp whenever D32 is available,
; including VFPv3 configurations without NEON. Test this without register
; clearing so an interrupt-specific clearing guard cannot hide a bad CSR list.
;
; RUN: llc -mtriple=armv7a-none-eabi -mattr=+vfp3,-neon -verify-machineinstrs %s -o - | FileCheck %s
; RUN: llc -mtriple=thumbv7a-none-eabi -mattr=+vfp3,-neon -verify-machineinstrs %s -o - | FileCheck %s
; RUN: llc -mtriple=armv7a-none-eabi -mattr=+neon -verify-machineinstrs %s -o - | FileCheck %s

define void @irq_save_d31() "interrupt"="IRQ" "save-fp" {
; CHECK-LABEL: irq_save_d31:
; CHECK:         vpush {d31}
; CHECK:         vmov.f64 d31, d31
; CHECK:         vpop {d31}
; CHECK:         subs pc, lr, #4
  call void asm sideeffect "vmov.f64 d31, d31", "~{d31}"()
  ret void
}

define void @fiq_save_d31() "interrupt"="FIQ" "save-fp" {
; CHECK-LABEL: fiq_save_d31:
; CHECK:         vpush {d31}
; CHECK:         vmov.f64 d31, d31
; CHECK:         vpop {d31}
; CHECK:         subs pc, lr, #4
  call void asm sideeffect "vmov.f64 d31, d31", "~{d31}"()
  ret void
}
