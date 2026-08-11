; A function carrying "zeroize-stack" clears its own frame before returning.
; Inlining it would dissolve that frame into the caller's and lose the
; obligation, so it is never inlined, whatever the caller is annotated with.
; Inlining an unannotated callee into an annotated caller is still allowed.

; RUN: opt < %s -passes=inline -S | FileCheck %s
; RUN: opt < %s -passes='default<O2>' -S | FileCheck %s --check-prefix=O2

declare void @sink(i32)

define void @zeroize_used_callee(i32 %x) "zeroize-stack"="used" {
  call void @sink(i32 %x)
  ret void
}

define void @zeroize_sensitive_callee(i32 %x) "zeroize-stack"="sensitive" {
  call void @sink(i32 %x)
  ret void
}

define void @plain_callee(i32 %x) {
  call void @sink(i32 %x)
  ret void
}

;; Not inlined into a caller that has no attribute: the caller clears nothing,
;; so the callee's frame bytes would be left behind.

define void @unannotated_caller(i32 %x) {
; CHECK-LABEL: define void @unannotated_caller(
; CHECK: call void @zeroize_used_callee(
; CHECK: call void @zeroize_sensitive_callee(
; CHECK-NOT: call void @sink(
;
; O2-LABEL: define void @unannotated_caller(
; O2: call void @zeroize_used_callee(
; O2: call void @zeroize_sensitive_callee(
; O2-NOT: call void @sink(
  call void @zeroize_used_callee(i32 %x)
  call void @zeroize_sensitive_callee(i32 %x)
  ret void
}

;; Not inlined into a caller that has the attribute either. The rule has no
;; same-attribute exemption: the caller's clear covers the caller's own frame at
;; the caller's returns, not the clear the callee owed where it would have
;; returned, and the two need not ask for the same amount of the frame.

define void @zeroize_used_caller(i32 %x) "zeroize-stack"="used" {
; CHECK-LABEL: define void @zeroize_used_caller(
; CHECK: call void @zeroize_used_callee(
; CHECK: call void @zeroize_sensitive_callee(
;
; O2-LABEL: define void @zeroize_used_caller(
; O2: call void @zeroize_used_callee(
; O2: call void @zeroize_sensitive_callee(
  call void @zeroize_used_callee(i32 %x)
  call void @zeroize_sensitive_callee(i32 %x)
  ret void
}

define void @zeroize_sensitive_caller(i32 %x) "zeroize-stack"="sensitive" {
; CHECK-LABEL: define void @zeroize_sensitive_caller(
; CHECK: call void @zeroize_used_callee(
; CHECK: call void @zeroize_sensitive_callee(
;
; O2-LABEL: define void @zeroize_sensitive_caller(
; O2: call void @zeroize_used_callee(
; O2: call void @zeroize_sensitive_callee(
  call void @zeroize_used_callee(i32 %x)
  call void @zeroize_sensitive_callee(i32 %x)
  ret void
}

;; An unannotated callee is still inlined into an annotated caller, and that is
;; the direction worth encouraging: the callee's frame sits below the stack
;; pointer at the caller's return and no clear reaches it, while inlining turns
;; those bytes into frame bytes the caller does clear.

define void @plain_into_zeroize_caller(i32 %x) "zeroize-stack"="used" {
; CHECK-LABEL: define void @plain_into_zeroize_caller(
; CHECK-NOT: call void @plain_callee(
; CHECK: call void @sink(
;
; O2-LABEL: define void @plain_into_zeroize_caller(
; O2-NOT: call void @plain_callee(
; O2: call void @sink(
  call void @plain_callee(i32 %x)
  ret void
}

define void @plain_into_sensitive_caller(i32 %x) "zeroize-stack"="sensitive" {
; CHECK-LABEL: define void @plain_into_sensitive_caller(
; CHECK-NOT: call void @plain_callee(
; CHECK: call void @sink(
;
; O2-LABEL: define void @plain_into_sensitive_caller(
; O2-NOT: call void @plain_callee(
; O2: call void @sink(
  call void @plain_callee(i32 %x)
  ret void
}
