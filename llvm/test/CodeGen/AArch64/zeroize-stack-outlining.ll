; RUN: llc -mtriple=aarch64-unknown-linux-gnu -O2 -verify-machineinstrs %s -o - | FileCheck %s

; Stack-clearing functions must keep their instructions in the function.
; Outlining remains enabled for ordinary minsize functions.

; CHECK-LABEL: used:
; CHECK-NOT: OUTLINED_FUNCTION
; CHECK-LABEL: sensitive:
; CHECK-NOT: OUTLINED_FUNCTION
; CHECK-LABEL: unprotected1:
; CHECK: {{b|bl}} OUTLINED_FUNCTION_
; CHECK-LABEL: unprotected2:
; CHECK: {{b|bl}} OUTLINED_FUNCTION_

define void @used() #0 {
  %a = alloca i32, align 4
  %b = alloca i32, align 4
  %c = alloca i32, align 4
  %d = alloca i32, align 4
  %e = alloca i32, align 4
  %f = alloca i32, align 4
  store i32 1, ptr %a, align 4
  store i32 2, ptr %b, align 4
  store i32 3, ptr %c, align 4
  store i32 4, ptr %d, align 4
  store i32 5, ptr %e, align 4
  store i32 6, ptr %f, align 4
  ret void
}

define void @sensitive() #1 {
  %a = alloca i32, align 4
  %b = alloca i32, align 4
  %c = alloca i32, align 4
  %d = alloca i32, align 4
  %e = alloca i32, align 4
  %f = alloca i32, align 4
  store i32 1, ptr %a, align 4
  store i32 2, ptr %b, align 4
  store i32 3, ptr %c, align 4
  store i32 4, ptr %d, align 4
  store i32 5, ptr %e, align 4
  store i32 6, ptr %f, align 4
  ret void
}

define void @unprotected1() #2 {
  %a = alloca i32, align 4
  %b = alloca i32, align 4
  %c = alloca i32, align 4
  %d = alloca i32, align 4
  %e = alloca i32, align 4
  %f = alloca i32, align 4
  store i32 1, ptr %a, align 4
  store i32 2, ptr %b, align 4
  store i32 3, ptr %c, align 4
  store i32 4, ptr %d, align 4
  store i32 5, ptr %e, align 4
  store i32 6, ptr %f, align 4
  ret void
}

define void @unprotected2() #2 {
  %a = alloca i32, align 4
  %b = alloca i32, align 4
  %c = alloca i32, align 4
  %d = alloca i32, align 4
  %e = alloca i32, align 4
  %f = alloca i32, align 4
  store i32 1, ptr %a, align 4
  store i32 2, ptr %b, align 4
  store i32 3, ptr %c, align 4
  store i32 4, ptr %d, align 4
  store i32 5, ptr %e, align 4
  store i32 6, ptr %f, align 4
  ret void
}

attributes #0 = { minsize optsize nounwind noredzone "zeroize-stack"="used" }
attributes #1 = { minsize optsize nounwind noredzone "zeroize-stack"="sensitive" }
attributes #2 = { minsize optsize nounwind noredzone }
