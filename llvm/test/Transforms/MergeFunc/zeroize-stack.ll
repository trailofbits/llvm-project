; Merging rewrites one of the two functions into a thunk that tail-calls the
; other, and the thunk is written from the attributes of the function it
; replaces. A thunk carrying "zeroize-stack" is undertaking to clear a frame
; that no longer holds what the attribute was asked for, and where the shared
; calling convention makes the thunk's call musttail the undertaking cannot be
; discharged at all, because control does not come back to the thunk. A
; protected function is left whole, which is what inlining already does with it.

; RUN: opt -passes=mergefunc -S < %s | FileCheck %s

declare void @sink(i32)
declare swifttailcc void @swiftsink(i32)

; Two identical protected functions stay two functions.
; CHECK: define void @protected_a(i32 %x) #0 {
; CHECK-NEXT: add i32 %x, 7
; CHECK: define void @protected_b(i32 %x) #0 {
; CHECK-NEXT: add i32 %x, 7
define void @protected_a(i32 %x) "zeroize-stack"="used" {
  %y = add i32 %x, 7
  call void @sink(i32 %y)
  ret void
}

define void @protected_b(i32 %x) "zeroize-stack"="used" {
  %y = add i32 %x, 7
  call void @sink(i32 %y)
  ret void
}

; The swifttailcc pair is the case that cannot be expressed at all: the thunk
; would musttail-call the body, and a protected function containing a musttail
; call does not verify. Leaving them unmerged is what keeps the pass from
; producing a module that the Verifier rejects.
; CHECK: define swifttailcc void @protected_swift_a(i32 %x) #0 {
; CHECK-NEXT: add i32 %x, 11
; CHECK: define swifttailcc void @protected_swift_b(i32 %x) #0 {
; CHECK-NEXT: add i32 %x, 11
define swifttailcc void @protected_swift_a(i32 %x) "zeroize-stack"="used" {
  %y = add i32 %x, 11
  tail call swifttailcc void @swiftsink(i32 %y)
  ret void
}

define swifttailcc void @protected_swift_b(i32 %x) "zeroize-stack"="used" {
  %y = add i32 %x, 11
  tail call swifttailcc void @swiftsink(i32 %y)
  ret void
}

; Nothing about merging in general changes: an identical pair without the
; attribute is still merged, so what is excluded is the attribute rather than
; this shape of function.
; CHECK: define void @plain_a(i32 %x) {
; CHECK-NEXT: add i32 %x, 13
; CHECK: define void @plain_b(i32 %0) {
; CHECK-NEXT: tail call void @plain_a(i32 %0)
define void @plain_a(i32 %x) {
  %y = add i32 %x, 13
  call void @sink(i32 %y)
  ret void
}

define void @plain_b(i32 %x) {
  %y = add i32 %x, 13
  call void @sink(i32 %y)
  ret void
}

; CHECK: attributes #0 = { "zeroize-stack"="used" }
