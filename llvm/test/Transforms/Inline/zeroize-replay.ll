; RUN: echo '' > %t.replay
; RUN: opt -passes=inline -verify-each -S %s | FileCheck %s
; RUN: opt -passes=inline -verify-each -cgscc-inline-replay=%t.replay \
; RUN:   -cgscc-inline-replay-scope=Module -cgscc-inline-replay-fallback=AlwaysInline \
; RUN:   -S %s | FileCheck %s

; Replay advice cannot bypass the independent stack and flags contracts.
define internal void @stack() "zeroize-stack"="used" {
  %p = alloca i32
  store volatile i32 42, ptr %p
  ret void
}

define internal void @flags() "zeroize-flags" {
  %p = alloca i32
  store volatile i32 7, ptr %p
  ret void
}

define void @plain_stack() {
; CHECK-LABEL: define void @plain_stack()
; CHECK: call void @stack()
  call void @stack()
  ret void
}

define void @plain_flags() {
; CHECK-LABEL: define void @plain_flags()
; CHECK: call void @flags()
  call void @flags()
  ret void
}

define void @narrow_stack() "zeroize-stack"="sensitive" {
; CHECK-LABEL: define void @narrow_stack()
; CHECK: call void @stack()
  call void @stack()
  ret void
}

define void @compatible() "zeroize-stack"="used" "zeroize-flags" {
; CHECK-LABEL: define void @compatible()
; CHECK-NOT: call void @stack()
; CHECK-NOT: call void @flags()
; CHECK: ret void
  call void @stack()
  call void @flags()
  ret void
}
