; RUN: llc -mtriple=x86_64-unknown-linux-gnu %s -o - 2>/dev/null | FileCheck %s

; These tail markers are not in tail position. Keep the calls and the work
; after them so that the protected functions return through their epilogues.

declare tailcc i32 @tailcc_callee(i32)
declare swifttailcc i32 @swifttailcc_callee(i32)
declare void @side_effect()

define tailcc i32 @protected_tailcc(i32 %x) "zeroize-stack"="used" {
; CHECK-LABEL: protected_tailcc:
; CHECK:       callq tailcc_callee@PLT
; CHECK:       incl %eax
; CHECK:       retq
  %r = tail call tailcc i32 @tailcc_callee(i32 %x)
  %sum = add i32 %r, 1
  ret i32 %sum
}

define swifttailcc i32 @protected_swifttailcc(i32 %x) "zeroize-stack"="sensitive" {
; CHECK-LABEL: protected_swifttailcc:
; CHECK:       callq swifttailcc_callee@PLT
; CHECK:       incl %eax
; CHECK:       retq
  %r = tail call swifttailcc i32 @swifttailcc_callee(i32 %x)
  %sum = add i32 %r, 1
  ret i32 %sum
}

define tailcc i32 @protected_different_result(i32 %x) "zeroize-stack"="used" {
; CHECK-LABEL: protected_different_result:
; CHECK:       callq tailcc_callee@PLT
; CHECK:       movl $42, %eax
; CHECK:       retq
  %r = tail call tailcc i32 @tailcc_callee(i32 %x)
  ret i32 42
}

define tailcc i32 @protected_call_follows(i32 %x) "zeroize-stack"="used" {
; CHECK-LABEL: protected_call_follows:
; CHECK:       callq tailcc_callee@PLT
; CHECK:       callq side_effect@PLT
; CHECK:       retq
  %r = tail call tailcc i32 @tailcc_callee(i32 %x)
  call void @side_effect()
  ret i32 %r
}
