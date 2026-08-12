; The fallbacks are not written in terms of any one target's instructions, and
; two of them are visible on a target that cannot clear anything at all: which
; exits are in scope is decided before any target is asked, and an unreadable
; mode is resolved before the target is asked too.
;
; trailofbits/vspells-ct-internal-notes#24.

; Both runs are under "not", because the widened mode reaches a refusal this
; target has to give and llc exits non-zero for it. That refusal is the second
; half of what is being tested.
; RUN: not llc -mtriple=armv7-unknown-linux-gnueabi -pei-print-clearing-sequence %s -o /dev/null 2>&1 | FileCheck --check-prefix=SEQ %s
; RUN: not llc -mtriple=armv7-unknown-linux-gnueabi %s -o /dev/null 2>&1 | FileCheck --check-prefix=DIAG %s

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

; An unreadable mode is not "skip". ARM cannot clear registers, so what the
; widened mode reaches here is the target's refusal, which is reported; what it
; does not do is quietly resolve to clearing nothing and say nothing.
; DIAG: error: {{.*}}in function unrecognized_mode i32 (i32): "zero-call-used-regs" is not supported by this target
define i32 @unrecognized_mode(i32 %x) "zero-call-used-regs"="a-mode-from-the-future" {
  ret i32 %x
}

; A mode that says to skip is read and honored, on this target as on any other,
; so it reaches no refusal.
; DIAG-NOT: in function skips_explicitly
define i32 @skips_explicitly(i32 %x) "zero-call-used-regs"="skip" {
  ret i32 %x
}
