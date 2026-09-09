; RUN: not llc -mtriple=aarch64-unknown-linux-gnu %s -o /dev/null 2>&1 | FileCheck %s
; RUN: not llc -mtriple=aarch64-unknown-linux-gnu -global-isel %s -o /dev/null 2>&1 | \
; RUN:   FileCheck %s

; Both instruction selectors diagnose an eligible guaranteed tail call in a
; protected function at the shared tail-position check.
; CHECK: error: cannot use guaranteed tail call in a function with the
; CHECK-SAME: "zeroize-stack" attribute
; CHECK-NOT: Broken module

declare tailcc i32 @callee(i32)

define tailcc i32 @protected(i32 %x) "zeroize-stack"="used" {
  %r = tail call tailcc i32 @callee(i32 %x)
  ret i32 %r
}
