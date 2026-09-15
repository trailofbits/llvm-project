; A musttail call must replace the caller, leaving no point to clear its frame.
; Reject it in protected functions; ordinary tail-call optimization is suppressed.

; RUN: not llvm-as < %s -o /dev/null 2>&1 | FileCheck %s

declare i32 @callee(i32)

; CHECK: cannot use musttail call in a function with the "zeroize-stack" attribute
; CHECK-NEXT: musttail call i32 @callee
define i32 @protected(i32 %x) "zeroize-stack"="used" {
  %r = musttail call i32 @callee(i32 %x)
  ret i32 %r
}

; The mode does not enter into it. Any mode is an undertaking to clear the
; frame, and none of them can be kept at a call that does not return.
; CHECK: cannot use musttail call in a function with the "zeroize-stack" attribute
; CHECK-NEXT: musttail call i32 @callee
define i32 @protected_sensitive(i32 %x) "zeroize-stack"="sensitive" {
  %r = musttail call i32 @callee(i32 %x)
  ret i32 %r
}

; A musttail call in a function that has not asked for the undertaking is
; untouched, so the attribute is what the rejection is about rather than
; musttail being newly restricted.
; CHECK-NOT: @unprotected
define i32 @unprotected(i32 %x) {
  %r = musttail call i32 @callee(i32 %x)
  ret i32 %r
}
