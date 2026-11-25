; REQUIRES: arm-registered-target || aarch64-registered-target || x86-registered-target
; RUN: %if arm-registered-target %{ llc -mtriple=armv7-linux-gnueabihf -O2 \
; RUN:   -enable-shrink-wrap -stop-after=shrink-wrap -verify-machineinstrs < %s | FileCheck %s %}
; RUN: %if arm-registered-target %{ llc -mtriple=thumbv7-linux-gnueabihf -O2 \
; RUN:   -enable-shrink-wrap -stop-after=shrink-wrap -verify-machineinstrs < %s | FileCheck %s %}
; RUN: %if aarch64-registered-target %{ llc -mtriple=aarch64-linux-gnu -O2 \
; RUN:   -enable-shrink-wrap -stop-after=shrink-wrap -verify-machineinstrs < %s | FileCheck %s %}
; RUN: %if x86-registered-target %{ llc -mtriple=x86_64-linux-gnu -O2 \
; RUN:   -enable-shrink-wrap -stop-after=shrink-wrap -verify-machineinstrs < %s | FileCheck %s %}

; The cold branch needs a frame. The early return must also allocate it
; in the protected function, since the epilogue clears it.

declare void @observe(ptr) nounwind

; CHECK-LABEL: name: protected
; CHECK-NOT: savePoint:
; CHECK-NOT: restorePoint:
; CHECK: body:
define i32 @protected(i1 %run) nounwind "zeroize-stack"="used" {
entry:
  %buf = alloca [64 x i8], align 8
  br i1 %run, label %frame, label %early, !prof !0

frame:
  store volatile i8 42, ptr %buf, align 8
  call void @observe(ptr %buf)
  ret i32 2

early:
  ret i32 3
}

; CHECK-LABEL: name: control
; CHECK: savePoint:
; CHECK-NEXT: - point: '%bb.[[COLD:[1-9][0-9]*]]'
; CHECK: restorePoint:
; CHECK-NEXT: - point: '%bb.[[COLD]]'
define i32 @control(i1 %run) nounwind {
entry:
  %buf = alloca [64 x i8], align 8
  br i1 %run, label %frame, label %early, !prof !0

frame:
  store volatile i8 42, ptr %buf, align 8
  call void @observe(ptr %buf)
  ret i32 2

early:
  ret i32 3
}

!0 = !{!"branch_weights", i32 1, i32 100}
