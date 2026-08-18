; The fallbacks are not written in terms of any one target's instructions:
; which exits are in scope is decided before any target is asked, and an
; unreadable mode is resolved before the target is asked too.
;
; trailofbits/vspells-ct-internal-notes#24.

; RUN: llc -mtriple=armv7-unknown-linux-gnueabi -pei-print-clearing-sequence %s -o /dev/null 2>&1 | FileCheck --check-prefix=SEQ %s
; RUN: llc -mtriple=armv7-unknown-linux-gnueabi %s -o - | FileCheck --check-prefix=ASM %s

@g = external global i32

declare void @llvm.trap()

; A supervisor call written as inline assembly ends the block, and whether
; control comes back from it is not something the compiler can decide. It is
; in scope here for the same reason it is on x86-64.
; SEQ-LABEL: clearing sequence for function 'opaque_asm':
; SEQ-NEXT:  %bb.0 unknown: clear-stack=not-requested clear-registers=not-requested clear-flags=unimplemented
; SEQ-NEXT:  end clearing sequence for function 'opaque_asm'
define void @opaque_asm(i32 %a, i32 %b) {
  %s = add i32 %a, %b
  store i32 %s, ptr @g
  call void asm sideeffect "svc #0", "~{memory}"()
  unreachable
}

; A trap is a trap on every target that marks one, and stays out of scope.
; SEQ-LABEL: clearing sequence for function 'traps':
; SEQ-NEXT:  end clearing sequence for function 'traps'
define void @traps() {
  call void @llvm.trap()
  unreachable
}

; An unreadable mode is not "skip", it is "all", and on a target that can clear
; its registers that is visible in what comes out: the general-purpose
; registers the exit does not need and the whole of the vector file it is
; allowed to touch. Resolving it to "skip" would leave the function looking
; exactly like the one below.
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

; A mode that says to skip is read and honored, on this target as on any other.
; This is the control for the case above: without it, that one would pass just
; as well if every mode cleared everything.
; ASM-LABEL: skips_explicitly:
; ASM-NOT:     mov r{{[0-9]+}}, #0
; ASM-NOT:     vmov
; ASM:         bx lr
define i32 @skips_explicitly(i32 %x) "zero-call-used-regs"="skip" {
  ret i32 %x
}
