; RUN: opt -passes=partial-inliner -skip-partial-inlining-cost-analysis \
; RUN:   -verify-each -S %s | FileCheck %s

declare void @sink(ptr)

define i32 @callee(i1 %early) "zeroize-stack"="used" "zeroize-flags" {
entry:
  %p = alloca i32
  store volatile i32 42, ptr %p
  br i1 %early, label %return, label %body

body:
  call void @sink(ptr %p)
  br label %return

return:
  %r = phi i32 [0, %entry], [1, %body]
  ret i32 %r
}

define i32 @caller(i1 %early) {
; CHECK-LABEL: define i32 @caller(
; CHECK-NOT: alloca
; CHECK: call i32 @callee(
  %r = call i32 @callee(i1 %early)
  ret i32 %r
}
