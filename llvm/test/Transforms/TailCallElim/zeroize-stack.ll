; RUN: opt -passes=tailcallelim -verify-each -S %s | FileCheck %s
; RUN: opt -passes='default<O2>' -verify-each -S %s | FileCheck %s

; Do not introduce a guaranteed tail call into a protected function. Check both
; the isolated pass and the optimization pipeline that normally marks calls.

declare tailcc i32 @tailcc_callee(i32)
declare swifttailcc i32 @swifttailcc_callee(i32)
declare tailcc i32 @readnone_callee() memory(none)
declare void @escape(ptr)
declare i32 @plain_callee(i32)

define tailcc i32 @protected_tailcc(i32 %x) "zeroize-stack"="used" {
; CHECK-LABEL: define tailcc i32 @protected_tailcc(
; CHECK:       %r = call tailcc i32 @tailcc_callee(i32 %x)
; CHECK-NEXT:  ret i32 %r
  %r = call tailcc i32 @tailcc_callee(i32 %x)
  ret i32 %r
}

define swifttailcc i32 @protected_swifttailcc(i32 %x) "zeroize-stack"="sensitive" {
; CHECK-LABEL: define swifttailcc i32 @protected_swifttailcc(
; CHECK:       %r = call swifttailcc i32 @swifttailcc_callee(i32 %x)
; CHECK-NEXT:  ret i32 %r
  %r = call swifttailcc i32 @swifttailcc_callee(i32 %x)
  ret i32 %r
}

; The readnone path can mark calls even after the local stack has escaped.
define tailcc i32 @protected_readnone() "zeroize-stack" {
; CHECK-LABEL: define tailcc i32 @protected_readnone(
; CHECK:       %r = call tailcc i32 @readnone_callee()
; CHECK:       ret i32 %r
  %slot = alloca i32
  store i32 42, ptr %slot
  call void @escape(ptr %slot)
  %r = call tailcc i32 @readnone_callee()
  ret i32 %r
}

define i32 @protected_plain(i32 %x) "zeroize-stack"="used" {
; CHECK-LABEL: define i32 @protected_plain(
; CHECK:       %r = call i32 @plain_callee(i32 %x)
; CHECK-NEXT:  ret i32 %r
  %r = call i32 @plain_callee(i32 %x)
  ret i32 %r
}

; Existing optional tail markers remain valid; CodeGen suppresses them.
define i32 @protected_existing_tail(i32 %x) "zeroize-stack"="used" {
; CHECK-LABEL: define i32 @protected_existing_tail(
; CHECK:       %r = tail call i32 @plain_callee(i32 %x)
; CHECK-NEXT:  ret i32 %r
  %r = tail call i32 @plain_callee(i32 %x)
  ret i32 %r
}

define tailcc i32 @unprotected_tailcc(i32 %x) {
; CHECK-LABEL: define tailcc i32 @unprotected_tailcc(
; CHECK:       %r = tail call tailcc i32 @tailcc_callee(i32 %x)
; CHECK-NEXT:  ret i32 %r
  %r = call tailcc i32 @tailcc_callee(i32 %x)
  ret i32 %r
}

define swifttailcc i32 @unprotected_swifttailcc(i32 %x) {
; CHECK-LABEL: define swifttailcc i32 @unprotected_swifttailcc(
; CHECK:       %r = tail call swifttailcc i32 @swifttailcc_callee(i32 %x)
; CHECK-NEXT:  ret i32 %r
  %r = call swifttailcc i32 @swifttailcc_callee(i32 %x)
  ret i32 %r
}
