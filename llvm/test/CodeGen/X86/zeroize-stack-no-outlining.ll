; RUN: llc -mtriple=x86_64-unknown-linux-gnu -mattr=+sahf \
; RUN:   -enable-machine-outliner=always -verify-machineinstrs %s -o - \
; RUN:   | FileCheck %s --implicit-check-not=OUTLINED_FUNCTION --implicit-check-not='pushq $'
;
; Outlining an epilogue must not insert a call after clearing the frame: the
; call would overwrite the cleared saved-register slot with a return address.
; CHECK-LABEL: frame_0:
; CHECK: addq $72, %rsp
; CHECK: sahf
; CHECK: retq
; CHECK-LABEL: frame_7:
; CHECK: addq $72, %rsp
; CHECK: sahf
; CHECK: retq

declare void @sink(ptr, i64)
define i64 @frame_0(i64 %x) minsize nounwind "zeroize-stack"="used" "zeroize-flags" {
  %p = alloca [64 x i8], align 16
  call void @sink(ptr %p, i64 0)
  %r = add i64 %x, 0
  ret i64 %r
}
define i64 @frame_1(i64 %x) minsize nounwind "zeroize-stack"="used" "zeroize-flags" {
  %p = alloca [64 x i8], align 16
  call void @sink(ptr %p, i64 1)
  %r = add i64 %x, 1
  ret i64 %r
}
define i64 @frame_2(i64 %x) minsize nounwind "zeroize-stack"="used" "zeroize-flags" {
  %p = alloca [64 x i8], align 16
  call void @sink(ptr %p, i64 2)
  %r = add i64 %x, 2
  ret i64 %r
}
define i64 @frame_3(i64 %x) minsize nounwind "zeroize-stack"="used" "zeroize-flags" {
  %p = alloca [64 x i8], align 16
  call void @sink(ptr %p, i64 3)
  %r = add i64 %x, 3
  ret i64 %r
}
define i64 @frame_4(i64 %x) minsize nounwind "zeroize-stack"="used" "zeroize-flags" {
  %p = alloca [64 x i8], align 16
  call void @sink(ptr %p, i64 4)
  %r = add i64 %x, 4
  ret i64 %r
}
define i64 @frame_5(i64 %x) minsize nounwind "zeroize-stack"="used" "zeroize-flags" {
  %p = alloca [64 x i8], align 16
  call void @sink(ptr %p, i64 5)
  %r = add i64 %x, 5
  ret i64 %r
}
define i64 @frame_6(i64 %x) minsize nounwind "zeroize-stack"="used" "zeroize-flags" {
  %p = alloca [64 x i8], align 16
  call void @sink(ptr %p, i64 6)
  %r = add i64 %x, 6
  ret i64 %r
}
define i64 @frame_7(i64 %x) minsize nounwind "zeroize-stack"="used" "zeroize-flags" {
  %p = alloca [64 x i8], align 16
  call void @sink(ptr %p, i64 7)
  %r = add i64 %x, 7
  ret i64 %r
}
