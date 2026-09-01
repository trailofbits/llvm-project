; A libcall the legalizer generates has no call in the IR behind it, so it is
; not caught where an IR call is. GlobalISel forms these libcalls on its own
; path, separate from SelectionDAG, and decides the tail call in the legalizer
; rather than in TargetLowering::isInTailCallPosition. The suppression is asked
; there too: a protected function keeps the call and returns through its own
; epilogue where an unprotected one branches away.

; RUN: llc -mtriple=aarch64-unknown-linux-gnu -global-isel %s -o - 2>/dev/null | FileCheck %s

; The "zeroize-stack" function also reports that no target clears the frame yet.
; That report is a warning, so llc still succeeds, and stderr is discarded here.

; CHECK-LABEL: protected_libcall:
; CHECK:         bl fmod
; CHECK:         ret
define double @protected_libcall(double %a, double %b) "zeroize-stack"="used" {
  %r = frem double %a, %b
  ret double %r
}

; CHECK-LABEL: unprotected_libcall:
; CHECK:         b fmod
define double @unprotected_libcall(double %a, double %b) {
  %r = frem double %a, %b
  ret double %r
}
