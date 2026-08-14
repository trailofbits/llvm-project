; Textual and bitcode round-trips of !nozeroize on an alloca.
; RUN: llvm-as < %s | llvm-dis | FileCheck %s
; RUN: llvm-as < %s | llvm-dis | llvm-as | llvm-dis | FileCheck %s

define void @marked() {
; CHECK-LABEL: define void @marked() {
; CHECK-NEXT:    [[LOOP_BOUND:%.*]] = alloca i64, align 8, !nozeroize [[META0:![0-9]+]]
; CHECK-NEXT:    ret void
;
  %loop_bound = alloca i64, align 8, !nozeroize !0
  ret void
}

; The metadata is a flag, so every marked object shares the one empty node. An
; object with no mark on it stays unmarked, which is what the "sensitive" mode
; of "zeroize-stack" clears.
define void @marked_twice() {
; CHECK-LABEL: define void @marked_twice() {
; CHECK-NEXT:    [[LENGTH:%.*]] = alloca i64, align 8, !nozeroize [[META0]]
; CHECK-NEXT:    [[INDEX:%.*]] = alloca i64, align 8, !nozeroize [[META0]]
; CHECK-NEXT:    [[KEY:%.*]] = alloca [176 x i8], align 16
; CHECK-NEXT:    ret void
;
  %length = alloca i64, align 8, !nozeroize !0
  %index = alloca i64, align 8, !nozeroize !0
  %key = alloca [176 x i8], align 16
  ret void
}

; Dropping the mark is the safe direction: this function is the one above with
; both marks gone, and every object in it is cleared.
define void @unmarked() {
; CHECK-LABEL: define void @unmarked() {
; CHECK-NEXT:    [[LENGTH:%.*]] = alloca i64, align 8{{$}}
; CHECK-NEXT:    [[INDEX:%.*]] = alloca i64, align 8{{$}}
; CHECK-NEXT:    [[KEY:%.*]] = alloca [176 x i8], align 16{{$}}
; CHECK-NEXT:    ret void
;
  %length = alloca i64, align 8
  %index = alloca i64, align 8
  %key = alloca [176 x i8], align 16
  ret void
}

!0 = !{}
;.
; CHECK: [[META0]] = !{}
;.
