; The suppression is decided in target-independent code, so it reaches a target
; that forms its tail calls differently. ARM turns a call in tail position into
; a branch; a protected function keeps the call and returns through its own
; epilogue instead.

; RUN: not llc -mtriple=armv7-unknown-linux-gnueabi %s -o - 2>/dev/null | FileCheck %s

; The "zeroize-stack" function also reports that no target clears the frame yet,
; which is what the `not` is for.

declare i32 @callee(i32)

; CHECK-LABEL: protected:
; CHECK:         bl callee
; CHECK:         pop {r11, pc}
define i32 @protected(i32 %x) "zeroize-stack"="used" {
  %r = tail call i32 @callee(i32 %x)
  ret i32 %r
}

; CHECK-LABEL: unprotected:
; CHECK:         b callee
define i32 @unprotected(i32 %x) {
  %r = tail call i32 @callee(i32 %x)
  ret i32 %r
}

; A libcall the legalizer generates has no call in the IR behind it, and is
; refused at the second place the tail-call question is asked.
; CHECK-LABEL: protected_libcall:
; CHECK:         bl fmod
; CHECK:         pop {r11, pc}
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
