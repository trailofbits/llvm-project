; CoroSplit lowers a presplit coroutine into resume/destroy clones that hand off
; with musttail calls (symmetric transfer, and the async coro.end) and copies the
; coroutine's function attributes onto those clones. A protected coroutine would
; therefore become a protected function holding a musttail call, which
; verifyMustTailCall rejects. That is the same conflict written one layer up: a
; function cannot both hand its frame off at a musttail call and clear that frame
; after it, so the combination is rejected before the split rather than aborting
; mid-CoroSplit with "Broken module found" on input that verified.

; RUN: not llvm-as < %s -o /dev/null 2>&1 | FileCheck %s

; CHECK: cannot use the "zeroize-stack" attribute on a coroutine
; CHECK-NEXT: ptr @protected_coro
define ptr @protected_coro() "zeroize-stack"="used" presplitcoroutine {
  ret ptr null
}

; The mode does not enter into it. Any mode is an undertaking to clear the frame,
; and none of them survives being handed off at a suspend point.
; CHECK: cannot use the "zeroize-stack" attribute on a coroutine
; CHECK-NEXT: ptr @protected_coro_sensitive
define ptr @protected_coro_sensitive() "zeroize-stack"="sensitive" presplitcoroutine {
  ret ptr null
}

; A coroutine that has not asked for the undertaking is untouched, so the
; attribute is what the rejection is about rather than coroutines being newly
; restricted.
; CHECK-NOT: @plain_coro
define ptr @plain_coro() presplitcoroutine {
  ret ptr null
}

; The attribute on an ordinary function is untouched here; the tail-call
; suppression and the musttail rule cover that function.
; CHECK-NOT: @protected_noncoro
define ptr @protected_noncoro() "zeroize-stack"="used" {
  ret ptr null
}
