; RUN: llvm-as %s -o /dev/null
; RUN: opt -passes='default<O2>' -verify-each -disable-output %s

; A tail marker does not imply tail position. A call whose result must be used
; by subsequent work has no guaranteed tail call to conflict with zeroization.

declare tailcc i32 @tailcc_callee(i32)
declare swifttailcc i32 @swifttailcc_callee(i32)
declare void @side_effect()

define tailcc i32 @tailcc_result_used(i32 %x) "zeroize-stack"="used" {
  %r = tail call tailcc i32 @tailcc_callee(i32 %x)
  %sum = add i32 %r, 1
  ret i32 %sum
}

define swifttailcc i32 @swifttailcc_result_used(i32 %x)
    "zeroize-stack"="sensitive" {
  %r = tail call swifttailcc i32 @swifttailcc_callee(i32 %x)
  %sum = add i32 %r, 1
  ret i32 %sum
}

; Simplification can expose tail position. The resulting IR remains valid;
; CodeGen diagnoses the conflict if the call becomes eligible for tail lowering.
define tailcc i32 @tailcc_simplifiable_result(i32 %x) "zeroize-stack"="used" {
  %r = tail call tailcc i32 @tailcc_callee(i32 %x)
  %sum = add i32 %r, 0
  ret i32 %sum
}

define tailcc i32 @tailcc_call_follows(i32 %x) "zeroize-stack"="used" {
  %r = tail call tailcc i32 @tailcc_callee(i32 %x)
  call void @side_effect()
  ret i32 %r
}

; Immediately preceding a return is insufficient when a different value must
; be returned after the call.
define tailcc i32 @tailcc_different_result(i32 %x) "zeroize-stack"="used" {
  %r = tail call tailcc i32 @tailcc_callee(i32 %x)
  ret i32 42
}

define tailcc i32 @tailcc_unmarked(i32 %x) "zeroize-stack"="used" {
  %r = call tailcc i32 @tailcc_callee(i32 %x)
  ret i32 %r
}

define tailcc i32 @tailcc_notail(i32 %x) "zeroize-stack"="used" {
  %r = notail call tailcc i32 @tailcc_callee(i32 %x)
  ret i32 %r
}

; Matching caller and callee conventions are required for the guarantee.
define i32 @tailcc_different_convention(i32 %x) "zeroize-stack"="used" {
  %r = tail call tailcc i32 @tailcc_callee(i32 %x)
  ret i32 %r
}
