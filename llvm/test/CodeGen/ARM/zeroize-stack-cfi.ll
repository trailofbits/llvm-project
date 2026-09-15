; RUN: llc -mtriple=armv7-none-eabi -exception-model=dwarf -verify-machineinstrs %s -o - | FileCheck %s
; RUN: llc -mtriple=thumbv6m-none-eabi -exception-model=dwarf -verify-machineinstrs %s -o - | FileCheck %s
; RUN: llc -mtriple=thumbv7m-none-eabi -exception-model=dwarf -verify-machineinstrs %s -o - | FileCheck %s
; RUN: llc -mtriple=armv7-none-eabi -exception-model=dwarf -filetype=obj %s -o /dev/null
; RUN: llc -mtriple=thumbv6m-none-eabi -exception-model=dwarf -filetype=obj %s -o /dev/null
; RUN: llc -mtriple=thumbv7m-none-eabi -exception-model=dwarf -filetype=obj %s -o /dev/null

; Switch CFA back to SP before restoring the frame pointer. Describe restored
; registers before erasing their slots, and release the frame only afterward.
; CHECK-LABEL: framed:
; CHECK: .cfi_def_cfa sp,
; CHECK: .cfi_restore {{r7|r11}}
; CHECK: str r2, [r1]
; CHECK: mov sp, r1
; CHECK-NEXT: .cfi_def_cfa sp, 0
; CHECK: bx lr
define i32 @framed(i32 %x) uwtable "frame-pointer"="all" "zeroize-stack"="used" {
  %p = alloca i32, align 4
  store volatile i32 %x, ptr %p
  ret i32 %x
}
