; RUN: llc -mtriple=aarch64-unknown-linux-gnu -aarch64-redzone -verify-machineinstrs %s -o - | \
; RUN: FileCheck %s
; RUN: llc -mtriple=aarch64-unknown-linux-gnu -aarch64-redzone -global-isel -global-isel-abort=1 \
; RUN: -verify-machineinstrs %s -o - | FileCheck %s

declare i64 @callee(i64)

; CHECK-LABEL: protected_leaf:
; CHECK: sub sp, sp, #16
; CHECK: stp xzr, xzr,
; CHECK: mov sp,
; CHECK: ret
define i64 @protected_leaf(i64 %x) "zeroize-stack"="used" {
  %p = alloca i64, align 8
  store volatile i64 %x, ptr %p
  ret i64 %x
}

; CHECK-LABEL: ordinary_leaf:
; CHECK-NOT: sub sp,
; CHECK-NOT: stp xzr,
; CHECK: stur x0, [sp, #-8]
; CHECK-NEXT: ret
define i64 @ordinary_leaf(i64 %x) {
  %p = alloca i64, align 8
  store volatile i64 %x, ptr %p
  ret i64 %x
}

; CHECK-LABEL: protected_tail:
; CHECK: bl callee
; CHECK: stp xzr, xzr,
; CHECK: ret
define i64 @protected_tail(i64 %x) "zeroize-stack"="used" {
  %r = tail call i64 @callee(i64 %x)
  ret i64 %r
}

; CHECK-LABEL: flags_tail:
; CHECK: bl callee
; CHECK: msr NZCV, xzr
; CHECK-NEXT: ret
define i64 @flags_tail(i64 %x) "zeroize-flags" {
  %r = tail call i64 @callee(i64 %x)
  ret i64 %r
}

; CHECK-LABEL: ordinary_tail:
; CHECK: b callee
define i64 @ordinary_tail(i64 %x) {
  %r = tail call i64 @callee(i64 %x)
  ret i64 %r
}
