; A function carrying "zeroize-stack" clears its own frame before returning.
; Inlining dissolves that frame into the caller's, so the callee is inlined only
; into a caller that carries the attribute as well and whose mode clears at least
; as much of the frame. "used" is the widest mode and any unrecognized mode is
; treated as "used", so "sensitive" is the only mode that clears less: a "used"
; caller takes a callee of either mode, a "sensitive" caller takes only a
; "sensitive" callee, and an unannotated caller takes neither. A callee that does
; not carry the attribute is unconstrained by this. A request to inline does not
; override the rule.

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

define void @zeroize_alwaysinline_callee(i32 %x) alwaysinline "zeroize-stack"="used" {
  call void @sink(i32 %x)
  ret void
}

;; Refused into a caller with no attribute, in either mode: the caller clears
;; nothing, so the bytes the callee promised to clear would be left behind.

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

;; Inlined into an equally protected caller: "used" into "used" clears the whole
;; frame on both sides, so the callee's bytes end up in a frame that is cleared.

define void @used_into_used_caller(i32 %x) "zeroize-stack"="used" {
; CHECK-LABEL: define void @used_into_used_caller(
; CHECK-NOT: call void @zeroize_used_callee(
; CHECK: call void @sink(
;
; O2-LABEL: define void @used_into_used_caller(
; O2-NOT: call void @zeroize_used_callee(
; O2: call void @sink(
  call void @zeroize_used_callee(i32 %x)
  ret void
}

;; "sensitive" into "sensitive": the caller asks for exactly what the callee did.

define void @sensitive_into_sensitive_caller(i32 %x) "zeroize-stack"="sensitive" {
; CHECK-LABEL: define void @sensitive_into_sensitive_caller(
; CHECK-NOT: call void @zeroize_sensitive_callee(
; CHECK: call void @sink(
;
; O2-LABEL: define void @sensitive_into_sensitive_caller(
; O2-NOT: call void @zeroize_sensitive_callee(
; O2: call void @sink(
  call void @zeroize_sensitive_callee(i32 %x)
  ret void
}

;; "sensitive" into "used": the caller clears more than the callee asked for,
;; which keeps the callee's guarantee and then some.

define void @sensitive_into_used_caller(i32 %x) "zeroize-stack"="used" {
; CHECK-LABEL: define void @sensitive_into_used_caller(
; CHECK-NOT: call void @zeroize_sensitive_callee(
; CHECK: call void @sink(
;
; O2-LABEL: define void @sensitive_into_used_caller(
; O2-NOT: call void @zeroize_sensitive_callee(
; O2: call void @sink(
  call void @zeroize_sensitive_callee(i32 %x)
  ret void
}

;; "used" into "sensitive" is refused, and this is the one pair where both
;; functions are protected and inlining is still wrong: the caller may spare
;; slots traced back to objects marked nozeroize, so it does not necessarily
;; clear everything the callee undertook to clear.

define void @used_into_sensitive_caller(i32 %x) "zeroize-stack"="sensitive" {
; CHECK-LABEL: define void @used_into_sensitive_caller(
; CHECK: call void @zeroize_used_callee(
; CHECK-NOT: call void @sink(
;
; O2-LABEL: define void @used_into_sensitive_caller(
; O2: call void @zeroize_used_callee(
; O2-NOT: call void @sink(
  call void @zeroize_used_callee(i32 %x)
  ret void
}

;; A callee without the attribute is still inlined into an annotated caller, and
;; that is the direction worth encouraging: the callee's frame sits below the
;; stack pointer at the caller's return and no clear reaches it, while inlining
;; turns those bytes into frame bytes the caller does clear.

define void @plain_into_used_caller(i32 %x) "zeroize-stack"="used" {
; CHECK-LABEL: define void @plain_into_used_caller(
; CHECK-NOT: call void @plain_callee(
; CHECK: call void @sink(
;
; O2-LABEL: define void @plain_into_used_caller(
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

;; A request to inline does not override the refusal, however it is spelled:
;; alwaysinline on the callee and on the call site both, into a caller that
;; clears nothing. The attribute compatibility check is bypassed on this path, so
;; this pins down that the rule is consulted there too.

define void @alwaysinline_caller(i32 %x) {
; CHECK-LABEL: define void @alwaysinline_caller(
; CHECK: call void @zeroize_alwaysinline_callee(
; CHECK-NOT: call void @sink(
;
; O2-LABEL: define void @alwaysinline_caller(
; O2: call void @zeroize_alwaysinline_callee(
; O2-NOT: call void @sink(
  call void @zeroize_alwaysinline_callee(i32 %x) alwaysinline
  ret void
}
