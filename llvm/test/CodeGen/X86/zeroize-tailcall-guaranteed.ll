; RUN: llvm-as %s -o /dev/null
; RUN: llvm-extract --func=protected_tailcc -S %s -o - | \
; RUN:   not llc -mtriple=x86_64-unknown-linux-gnu -o /dev/null 2>&1 | FileCheck %s
; RUN: llvm-extract --func=protected_tailcc -S %s -o - | \
; RUN:   not llc -mtriple=x86_64-unknown-linux-gnu -fast-isel -o /dev/null 2>&1 | \
; RUN:   FileCheck %s
; RUN: llvm-extract --func=protected_tailcc_sensitive -S %s -o - | \
; RUN:   not llc -mtriple=x86_64-unknown-linux-gnu -o /dev/null 2>&1 | FileCheck %s
; RUN: llvm-extract --func=protected_swifttailcc -S %s -o - | \
; RUN:   not llc -mtriple=x86_64-unknown-linux-gnu -o /dev/null 2>&1 | FileCheck %s
; RUN: llvm-extract --func=protected_tailcc_void -S %s -o - | \
; RUN:   not llc -mtriple=x86_64-unknown-linux-gnu -o /dev/null 2>&1 | FileCheck %s
; RUN: llvm-extract --func=protected_after_simplification -S %s -o - | \
; RUN:   opt -passes=instcombine -verify-each -S | \
; RUN:   not llc -mtriple=x86_64-unknown-linux-gnu -o /dev/null 2>&1 | FileCheck %s

; Unlike musttail, the guarantee from these conventions depends on the call's
; position. IR transformations may expose that position, so diagnose the
; conflict in CodeGen instead of making an optimization produce invalid IR.

; CHECK: error: cannot use guaranteed tail call in a function with the
; CHECK-SAME: "zeroize-stack" attribute
; CHECK-NOT: Broken module

declare tailcc i32 @tailcc_callee(i32)
declare swifttailcc i32 @swifttailcc_callee(i32)
declare tailcc void @tailcc_void_callee()

define tailcc i32 @protected_tailcc(i32 %x) "zeroize-stack"="used" {
  %r = tail call tailcc i32 @tailcc_callee(i32 %x)
  ret i32 %r
}

define tailcc i32 @protected_tailcc_sensitive(i32 %x) "zeroize-stack"="sensitive" {
  %r = tail call tailcc i32 @tailcc_callee(i32 %x)
  ret i32 %r
}

define swifttailcc i32 @protected_swifttailcc(i32 %x) "zeroize-stack"="used" {
  %r = tail call swifttailcc i32 @swifttailcc_callee(i32 %x)
  ret i32 %r
}

define tailcc void @protected_tailcc_void() "zeroize-stack"="used" {
  tail call tailcc void @tailcc_void_callee()
  ret void
}

define tailcc i32 @protected_after_simplification(i32 %x) "zeroize-stack"="used" {
  %r = tail call tailcc i32 @tailcc_callee(i32 %x)
  %sum = add i32 %r, 0
  ret i32 %sum
}
