; On Windows the clearing sequence lands inside the annotated epilogue, so
; each clear needs a no-op unwind code at its width or the object cannot be
; written. The assembly shows the directives; writing the object checks the
; sizes.

; RUN: llc -mtriple=thumbv7-windows-msvc -verify-machineinstrs %s -o - | FileCheck %s
; RUN: llc -mtriple=thumbv7-windows-msvc -verify-machineinstrs -filetype=obj %s -o %t.obj
; RUN: llvm-readobj --unwind %t.obj | FileCheck %s --check-prefix=UNWIND

declare void @sink()

; The clears carry the epilogue's flag, so the size reduction leaves them at
; the width their codes recorded.
define void @gpr() uwtable "zero-call-used-regs"="all-gpr" {
; CHECK-LABEL: gpr:
; CHECK:         bl sink
; CHECK-NEXT:    .seh_startepilogue
; CHECK-NEXT:    mov.w r0, #0
; CHECK-NEXT:    .seh_nop_w
; CHECK-NEXT:    mov.w r1, #0
; CHECK-NEXT:    .seh_nop_w
; CHECK-NEXT:    mov.w r2, #0
; CHECK-NEXT:    .seh_nop_w
; CHECK-NEXT:    mov.w r3, #0
; CHECK-NEXT:    .seh_nop_w
; CHECK-NEXT:    mov.w r12, #0
; CHECK-NEXT:    .seh_nop_w
; CHECK-NEXT:    pop.w {r11, pc}
; CHECK-NEXT:    .seh_save_regs_w {r11, lr}
; CHECK-NEXT:    .seh_endepilogue
;
; UNWIND-LABEL: Function: gpr
; UNWIND:       Epilogue [
; UNWIND-NEXT:    0xfc ; nop.w
; UNWIND-NEXT:    0xfc ; nop.w
; UNWIND-NEXT:    0xfc ; nop.w
; UNWIND-NEXT:    0xfc ; nop.w
; UNWIND-NEXT:    0xfc ; nop.w
; UNWIND-NEXT:    0xa8 0x00 ; pop.w {r11, pc}
; UNWIND-NEXT:  ]
  call void @sink()
  ret void
}

; The vector clears are wide too, and get the same code.
define void @all() uwtable "zero-call-used-regs"="all" {
; CHECK-LABEL: all:
; CHECK:         .seh_startepilogue
; CHECK:         mov.w r12, #0
; CHECK-NEXT:    .seh_nop_w
; CHECK-NEXT:    vmov.i32 q0, #0x0
; CHECK-NEXT:    .seh_nop_w
; CHECK:         vmov.i32 q15, #0x0
; CHECK-NEXT:    .seh_nop_w
; CHECK-NEXT:    pop.w {r11, pc}
; CHECK-NEXT:    .seh_save_regs_w {r11, lr}
; CHECK-NEXT:    .seh_endepilogue
;
; UNWIND-LABEL: Function: all
; UNWIND:       Epilogue [
; UNWIND-COUNT-17: 0xfc ; nop.w
; UNWIND-NEXT:    0xa8 0x00 ; pop.w {r11, pc}
; UNWIND-NEXT:  ]
  call void @sink()
  ret void
}

; The return value is left alone; the cleared argument sits in front of a
; narrow pop.
define i32 @used(i32 %a, i32 %b) uwtable "zero-call-used-regs"="used" {
; CHECK-LABEL: used:
; CHECK:         .seh_startepilogue
; CHECK-NEXT:    mov.w r1, #0
; CHECK-NEXT:    .seh_nop_w
; CHECK-NEXT:    pop {r4, pc}
; CHECK-NEXT:    .seh_save_regs {r4, lr}
; CHECK-NEXT:    .seh_endepilogue
;
; UNWIND-LABEL: Function: used
; UNWIND:       Epilogue [
; UNWIND-NEXT:    0xfc ; nop.w
; UNWIND-NEXT:    0xd4 ; pop {r4, pc}
; UNWIND-NEXT:  ]
  call void @sink()
  %x = mul i32 %a, %b
  ret i32 %x
}

; Without a frame there is no annotated epilogue, so the clear needs no code
; and stays narrow.
define i32 @leaf(i32 %a, i32 %b) uwtable "zero-call-used-regs"="used" {
; CHECK-LABEL: leaf:
; CHECK:         muls r0, r1, r0
; CHECK-NEXT:    movs r1, #0
; CHECK-NEXT:    bx lr
; CHECK-NOT:     .seh_
  %x = mul i32 %a, %b
  ret i32 %x
}
