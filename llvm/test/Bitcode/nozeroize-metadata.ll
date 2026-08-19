; !nozeroize has to come back from bitcode on the same allocas it went in on.
; Losing an attachment on reload would leave the object out of the set the
; "sensitive" mode clears while the module still reads as having asked for it,
; and moving one onto a neighbouring alloca would misdescribe the frame, so
; check which allocas carry the mark on reload rather than only that the module
; reloads. The second trip pins the first as a fixed point.

; RUN: llvm-as < %s | llvm-dis > %t.ll
; RUN: FileCheck %s < %t.ll
; RUN: llvm-as < %t.ll | llvm-dis > %t2.ll
; RUN: diff %t.ll %t2.ll

; CHECK-LABEL: define void @marked() {
; CHECK-NEXT: %key = alloca i64, align 8, !nozeroize [[EMPTY:![0-9]+]]
; CHECK-NEXT: %scratch = alloca i64, align 8{{$}}
; CHECK-NEXT: %round_keys = alloca [176 x i8], align 16, !nozeroize [[EMPTY]]
; CHECK-NEXT: ret void
define void @marked() {
  %key = alloca i64, align 8, !nozeroize !0
  %scratch = alloca i64, align 8
  %round_keys = alloca [176 x i8], align 16, !nozeroize !0
  ret void
}

; The node is shared, and every marked object in the module refers to the one
; empty node. A reload that gave each attachment its own node would still be
; correct, but a reload that lost the sharing across functions has usually lost
; the attachment as well, so check it.
; CHECK-LABEL: define void @marked_in_another_function() {
; CHECK-NEXT: %nonce = alloca i64, align 8, !nozeroize [[EMPTY]]
; CHECK-NEXT: ret void
define void @marked_in_another_function() {
  %nonce = alloca i64, align 8, !nozeroize !0
  ret void
}

; An unmarked function has to reload with nothing attached: an attachment
; appearing here would shrink what the "sensitive" mode clears to a set that
; was never described.
; CHECK-LABEL: define void @unmarked() {
; CHECK-NEXT: %scratch = alloca i64, align 8{{$}}
; CHECK-NEXT: ret void
define void @unmarked() {
  %scratch = alloca i64, align 8
  ret void
}

!0 = !{}

; The kind has to reload under its name, not as an anonymous numbered kind, and
; the node has to stay empty.
; CHECK: [[EMPTY]] = !{}
