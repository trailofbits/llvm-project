; Exit scope and unreadable modes are resolved before asking the target.
; trailofbits/vspells-ct-internal-notes#24.

; RUN: llc -mtriple=armv7-unknown-linux-gnueabi -pei-print-clearing-sequence %s -o /dev/null 2>&1 | FileCheck --check-prefix=SEQ %s
; RUN: llc -mtriple=armv7-unknown-linux-gnueabi %s -o - | FileCheck --check-prefix=ASM %s

@g = external global i32

declare void @llvm.trap()

; A supervisor call written as inline asm ends the block; whether control
; comes back is not something the compiler can decide.
; SEQ-LABEL: clearing sequence for function 'opaque_asm':
; SEQ-NEXT:  %bb.0 unknown: clear-stack=not-requested clear-registers=not-requested clear-flags=unimplemented
; SEQ-NEXT:  end clearing sequence for function 'opaque_asm'
define void @opaque_asm(i32 %a, i32 %b) {
  %s = add i32 %a, %b
  store i32 %s, ptr @g
  call void asm sideeffect "svc #0", "~{memory}"()
  unreachable
}

; A trap stays out of scope.
; SEQ-LABEL: clearing sequence for function 'traps':
; SEQ-NEXT:  end clearing sequence for function 'traps'
define void @traps() {
  call void @llvm.trap()
  unreachable
}

; An unreadable mode widens to "all", clearing the registers the exit can spare.
; ASM-LABEL: unrecognized_mode:
; ASM:         vmov.i32 q0, #0x0
; ASM:         mov r2, #0
; ASM:         mov r3, #0
; ASM:         mov r12, #0
; ASM:         vmov.i32 q15, #0x0
; ASM:         bx lr
define i32 @unrecognized_mode(i32 %x) "zero-call-used-regs"="a-mode-from-the-future" {
  ret i32 %x
}

; "skip" is honored and clears no registers.
; ASM-LABEL: skips_explicitly:
; ASM-NOT:     mov r{{[0-9]+}}, #0
; ASM-NOT:     vmov
; ASM:         bx lr
define i32 @skips_explicitly(i32 %x) "zero-call-used-regs"="skip" {
  ret i32 %x
}
