; Thumb-1 materializes one zero and copies it into the other registers. Before
; v6 the flags-free copy needs a high register on one side, so a low register
; is cleared directly by the flag-setting move instead; r12 still takes the
; copy. The verifier rejects the bad copy and object emission does not, so
; both are checked.

; RUN: llc -mtriple=thumbv4t-none-eabi -verify-machineinstrs %s -o - | FileCheck %s --check-prefix=PREV6
; RUN: llc -mtriple=thumbv5te-none-eabi -verify-machineinstrs %s -o - | FileCheck %s --check-prefix=PREV6
; RUN: llc -mtriple=thumbv4t-none-eabi -verify-machineinstrs -filetype=obj %s -o /dev/null
; RUN: llc -mtriple=thumbv5te-none-eabi -verify-machineinstrs -filetype=obj %s -o /dev/null
; RUN: llc -mtriple=thumbv6m-none-eabi -verify-machineinstrs %s -o - | FileCheck %s --check-prefix=V6

; Every call-used general-purpose register, low and high.
define void @all() "zero-call-used-regs"="all" {
; PREV6-LABEL: all:
; PREV6:         movs r0, #0
; PREV6-NEXT:    movs r1, #0
; PREV6-NEXT:    movs r2, #0
; PREV6-NEXT:    movs r3, #0
; PREV6-NEXT:    mov r12, r0
; PREV6-NEXT:    bx lr
;
; V6-LABEL: all:
; V6:         movs r0, #0
; V6-NEXT:    mov r1, r0
; V6-NEXT:    mov r2, r0
; V6-NEXT:    mov r3, r0
; V6-NEXT:    mov r12, r0
; V6-NEXT:    bx lr
  ret void
}

; Only the low registers the function used, with the return value left alone.
define i32 @used(i32 %a, i32 %b, i32 %c) "zero-call-used-regs"="used-gpr" {
; PREV6-LABEL: used:
; PREV6:         orrs
; PREV6-NEXT:    movs r1, #0
; PREV6-NEXT:    movs r2, #0
; PREV6-NEXT:    bx lr
;
; V6-LABEL: used:
; V6:         orrs
; V6-NEXT:    movs r1, #0
; V6-NEXT:    mov r2, r1
; V6-NEXT:    bx lr
  %x = mul i32 %a, %b
  %y = or i32 %x, %c
  ret i32 %y
}
