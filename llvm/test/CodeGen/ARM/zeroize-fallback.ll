; Two of the fallbacks are decided before any target is asked, so they show on
; a target that cannot clear anything. trailofbits/vspells-ct-internal-notes#24.

; Both runs are under "not": the widened mode reaches this target's refusal,
; and llc exits non-zero for it.
; RUN: not llc -mtriple=armv7-unknown-linux-gnueabi -pei-print-clearing-sequence %s -o /dev/null 2>&1 | FileCheck --check-prefix=SEQ %s
; RUN: not llc -mtriple=armv7-unknown-linux-gnueabi %s -o /dev/null 2>&1 | FileCheck --check-prefix=DIAG %s

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

; An unreadable mode is not "skip": it widens to "all", which this target
; refuses and reports.
; DIAG: error: {{.*}}in function unrecognized_mode i32 (i32): "zero-call-used-regs" is not supported by this target
define i32 @unrecognized_mode(i32 %x) "zero-call-used-regs"="a-mode-from-the-future" {
  ret i32 %x
}

; "skip" is honored and reaches no refusal.
; DIAG-NOT: in function skips_explicitly
define i32 @skips_explicitly(i32 %x) "zero-call-used-regs"="skip" {
  ret i32 %x
}
