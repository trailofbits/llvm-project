; A tail marker is ordinarily an optimization hint, so CodeGen can suppress it
; when the caller must clear its frame. tailcc and swifttailcc instead guarantee
; eligible tail calls. Reject that conflict rather than silently breaking the
; calling-convention contract.

; RUN: not llvm-as < %s -o /dev/null 2>&1 | FileCheck %s

declare tailcc i32 @tailcc_callee(i32)
declare swifttailcc i32 @swifttailcc_callee(i32)
declare i32 @plain_callee(i32)

; CHECK: cannot use guaranteed tail call in a function with the
; CHECK-SAME: "zeroize-stack" attribute
; CHECK-NEXT: tail call tailcc i32 @tailcc_callee
define tailcc i32 @protected_tailcc(i32 %x) "zeroize-stack"="used" {
  %r = tail call tailcc i32 @tailcc_callee(i32 %x)
  ret i32 %r
}

; The mode does not affect the conflict.
; CHECK: cannot use guaranteed tail call in a function with the
; CHECK-SAME: "zeroize-stack" attribute
; CHECK-NEXT: tail call tailcc i32 @tailcc_callee
define tailcc i32 @protected_tailcc_sensitive(i32 %x)
    "zeroize-stack"="sensitive" {
  %r = tail call tailcc i32 @tailcc_callee(i32 %x)
  ret i32 %r
}

; swifttailcc carries the same guarantee.
; CHECK: cannot use guaranteed tail call in a function with the
; CHECK-SAME: "zeroize-stack" attribute
; CHECK-NEXT: tail call swifttailcc i32 @swifttailcc_callee
define swifttailcc i32 @protected_swifttailcc(i32 %x)
    "zeroize-stack"="used" {
  %r = tail call swifttailcc i32 @swifttailcc_callee(i32 %x)
  ret i32 %r
}

; An ordinary tail marker remains an optional optimization and may be
; suppressed to honor zeroize-stack.
; CHECK-NOT: @protected_optional_tail
define i32 @protected_optional_tail(i32 %x) "zeroize-stack"="used" {
  %r = tail call i32 @plain_callee(i32 %x)
  ret i32 %r
}

; The convention alone is compatible with zeroize-stack when the function has
; no guaranteed tail call to suppress.
; CHECK-NOT: @protected_tailcc_without_tail
define tailcc i32 @protected_tailcc_without_tail(i32 %x)
    "zeroize-stack"="used" {
  ret i32 %x
}

; A guaranteed tail call without zeroize-stack remains valid.
; CHECK-NOT: @plain_tailcc
define tailcc i32 @plain_tailcc(i32 %x) {
  %r = tail call tailcc i32 @tailcc_callee(i32 %x)
  ret i32 %r
}
