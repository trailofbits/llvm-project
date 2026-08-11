; !sensitive marks a stack object, and its presence is the entire signal. Reject
; it where there is no stack object to mark, and reject a payload while the
; contents of the node are still reserved.

; RUN: not opt -passes=verify -disable-output < %s 2>&1 | FileCheck %s

; A global is not a stack object and nothing clears it on return, so an
; attachment here would be a request that is silently never honored.
; CHECK-DAG: !sensitive metadata can only be applied to alloca instructions
; CHECK-DAG: ptr @global
@global = global i64 0, !sensitive !0

; CHECK-DAG: !sensitive metadata can only be applied to alloca instructions
; CHECK-DAG: ptr @on_function
define void @on_function() !sensitive !0 {
  ret void
}

; CHECK-DAG: !sensitive metadata can only be applied to alloca instructions
; CHECK-DAG: store i64 %v, ptr %p, align 8, !sensitive !0
define void @on_store(ptr %p, i64 %v) {
  store i64 %v, ptr %p, align 8, !sensitive !0
  ret void
}

; The object an alloca allocates is one the "sensitive" mode can clear, but a
; load from it is not, so the mark belongs on the alloca and not on the access.
; CHECK-DAG: !sensitive metadata can only be applied to alloca instructions
; CHECK-DAG: %v = load i64, ptr %key, align 8, !sensitive !0
define i64 @on_load_of_marked_object() {
  %key = alloca i64, align 8, !sensitive !0
  %v = load i64, ptr %key, align 8, !sensitive !0
  ret i64 %v
}

; CHECK-DAG: !sensitive metadata must be empty
; CHECK-DAG: %key = alloca i64, align 8, !sensitive !1
define void @payload_string() {
  %key = alloca i64, align 8, !sensitive !1
  ret void
}

; CHECK-DAG: !sensitive metadata must be empty
; CHECK-DAG: %key = alloca i64, align 8, !sensitive !2
define void @payload_constant() {
  %key = alloca i64, align 8, !sensitive !2
  ret void
}

!0 = !{}
!1 = !{!"round keys"}
!2 = !{i32 1}
