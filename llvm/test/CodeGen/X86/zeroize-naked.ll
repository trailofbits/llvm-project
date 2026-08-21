; RUN: llc -mtriple=x86_64-unknown-linux-gnu < %s -o /dev/null 2>&1 | \
; RUN:   FileCheck %s --implicit-check-not='in function plain_naked' \
; RUN:     --implicit-check-not='in function naked_skip' \
; RUN:     --implicit-check-not='in function not_naked_regs'

; PEI generates no frame for a naked function, so "zeroize-stack" cannot be
; honored on any target. The message names the attribute rather than the target
; so it stays true once some target implements clearing; contrast
; zeroize-stack-unsupported.ll. llc runs without "not" to pin that it warns.
;
; --implicit-check-not, not a trailing CHECK-NOT, which would only scan past the
; last positive match and go vacuously true if these were reordered.

; CHECK: warning: {{.*}}in function naked_stack void (): "zeroize-stack" ignored on a "naked" function: no frame is generated to clear
define void @naked_stack() naked "zeroize-stack"="used" {
  call void asm sideeffect "nop", ""()
  ret void
}

; The mode makes no difference; none can be honored without a frame.
; CHECK: warning: {{.*}}in function naked_stack_sensitive void (): "zeroize-stack" ignored on a "naked" function: no frame is generated to clear
define void @naked_stack_sensitive() naked "zeroize-stack"="sensitive" {
  call void asm sideeffect "nop", ""()
  ret void
}

; A naked function that asks for no clearing has nothing to report.
define void @plain_naked() naked {
  call void asm sideeffect "nop", ""()
  ret void
}

; Control: a non-naked function still gets the target-worded report.
; CHECK: warning: {{.*}}in function not_naked i32 (i32): "zeroize-stack" is not supported by this target
define i32 @not_naked(i32 %x) "zeroize-stack"="used" {
  ret i32 %x
}

; Register clearing is emitted into the epilogue, which a naked function also
; does not have.
; CHECK: warning: {{.*}}in function naked_regs void (): "zero-call-used-regs" ignored on a "naked" function: no epilogue is generated to clear in
define void @naked_regs() naked "zero-call-used-regs"="all" {
  call void asm sideeffect "nop", ""()
  ret void
}

; "skip" asks for no clearing, so nothing is ignored. This must stay silent: the
; attribute is often set to "skip" wholesale, which would otherwise make naked
; functions unwritable in a translation unit that opts out.
define void @naked_skip() naked "zero-call-used-regs"="skip" {
  call void asm sideeffect "nop", ""()
  ret void
}

; Control: x86 does clear call-used registers, so a non-naked function is
; compiled with the clearing and not reported at all.
define i32 @not_naked_regs(i32 %x) "zero-call-used-regs"="all" {
  ret i32 %x
}
