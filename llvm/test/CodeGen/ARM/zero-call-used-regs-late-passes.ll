; Thumb-1 clears registers by copying a zero source. Check that target-aware
; copy propagation in the full pipeline preserves those copies and the return
; value. Generic retention bookkeeping is covered by the CodeGen tests.

; RUN: llc -mtriple=thumbv6m-none-eabi -mcp-use-is-copy-instr -verify-machineinstrs %s -o - | FileCheck %s --check-prefix=ASM

; The return value stays in r0; the used arguments in r1 and r2 are cleared.
define i32 @used(i32 %a, i32 %b, i32 %c) "zero-call-used-regs"="used-gpr" {
; ASM-LABEL: used:
; ASM:         orrs r0, r2
; ASM-NEXT:    movs r1, #0
; ASM-NEXT:    mov r2, r1
; ASM-NEXT:    bx lr
  %x = mul i32 %a, %b
  %y = or i32 %x, %c
  ret i32 %y
}

; Clear every call-used GPR, including the high register r12.
define void @all() "zero-call-used-regs"="all" {
; ASM-LABEL: all:
; ASM:         movs r0, #0
; ASM-NEXT:    mov r1, r0
; ASM-NEXT:    mov r2, r0
; ASM-NEXT:    mov r3, r0
; ASM-NEXT:    mov r12, r0
; ASM-NEXT:    bx lr
  ret void
}

; Only r12 was requested, but Thumb-1 also needs a low register holding zero.
define void @scratch() "zero-call-used-regs"="used-gpr" {
; ASM-LABEL: scratch:
; ASM:         movs r0, #0
; ASM-NEXT:    mov r12, r0
; ASM-NEXT:    bx lr
  call void asm sideeffect "", "~{r12}"()
  ret void
}
