; Textual and bitcode round-trips of !sensitive on an alloca.
; RUN: llvm-as < %s | llvm-dis | FileCheck %s
; RUN: llvm-as < %s | llvm-dis | llvm-as | llvm-dis | FileCheck %s

define void @marked() {
; CHECK-LABEL: define void @marked() {
; CHECK-NEXT:    [[ROUND_KEYS:%.*]] = alloca [176 x i8], align 16, !sensitive [[META0:![0-9]+]]
; CHECK-NEXT:    ret void
;
  %round_keys = alloca [176 x i8], align 16, !sensitive !0
  ret void
}

; The metadata is a flag, so every marked object shares the one empty node.
define void @marked_twice() {
; CHECK-LABEL: define void @marked_twice() {
; CHECK-NEXT:    [[KEY:%.*]] = alloca i64, align 8, !sensitive [[META0]]
; CHECK-NEXT:    [[NONCE:%.*]] = alloca i64, align 8, !sensitive [[META0]]
; CHECK-NEXT:    [[SCRATCH:%.*]] = alloca i64, align 8
; CHECK-NEXT:    ret void
;
  %key = alloca i64, align 8, !sensitive !0
  %nonce = alloca i64, align 8, !sensitive !0
  %scratch = alloca i64, align 8
  ret void
}

!0 = !{}
;.
; CHECK: [[META0]] = !{}
;.
