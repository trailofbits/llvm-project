; RUN: llc -mtriple=x86_64-unknown-linux-gnu -stop-before=prolog-epilog %s -o - | FileCheck %s
; RUN: not llc -mtriple=x86_64-unknown-linux-gnu %s -o /dev/null 2>&1 \
; RUN:   | FileCheck %s --check-prefix=DIAG

; These tail markers are not in tail position. Keep the calls and the work
; after them. The later epilogue rejects these callee-pop calling conventions
; because stack clearing only supports ordinary C and fastcc returns.

declare tailcc i32 @tailcc_callee(i32)
declare swifttailcc i32 @swifttailcc_callee(i32)
declare void @side_effect()

define tailcc i32 @protected_tailcc(i32 %x) "zeroize-stack"="used" {
; CHECK-LABEL: name: protected_tailcc
; CHECK:       CALL64pcrel32 {{.*}}@tailcc_callee
; CHECK:       INC32r
; CHECK:       RET 8
; DIAG: error: {{.*}}in function protected_tailcc {{.*}}X86 stack clearing does not support
  %r = tail call tailcc i32 @tailcc_callee(i32 %x)
  %sum = add i32 %r, 1
  ret i32 %sum
}

define swifttailcc i32 @protected_swifttailcc(i32 %x) "zeroize-stack"="sensitive" {
; CHECK-LABEL: name: protected_swifttailcc
; CHECK:       CALL64pcrel32 {{.*}}@swifttailcc_callee
; CHECK:       INC32r
; CHECK:       RET 8
; DIAG: error: {{.*}}in function protected_swifttailcc {{.*}}X86 stack clearing does not support
  %r = tail call swifttailcc i32 @swifttailcc_callee(i32 %x)
  %sum = add i32 %r, 1
  ret i32 %sum
}

define tailcc i32 @protected_different_result(i32 %x) "zeroize-stack"="used" {
; CHECK-LABEL: name: protected_different_result
; CHECK:       CALL64pcrel32 {{.*}}@tailcc_callee
; CHECK:       MOV32ri 42
; CHECK:       RET 8
; DIAG: error: {{.*}}in function protected_different_result
; DIAG-SAME: {{ .*}}X86 stack clearing does not support
  %r = tail call tailcc i32 @tailcc_callee(i32 %x)
  ret i32 42
}

define tailcc i32 @protected_call_follows(i32 %x) "zeroize-stack"="used" {
; CHECK-LABEL: name: protected_call_follows
; CHECK:       CALL64pcrel32 {{.*}}@tailcc_callee
; CHECK:       CALL64pcrel32 {{.*}}@side_effect
; CHECK:       RET 8
; DIAG: error: {{.*}}in function protected_call_follows {{.*}}X86 stack clearing does not support
  %r = tail call tailcc i32 @tailcc_callee(i32 %x)
  call void @side_effect()
  ret i32 %r
}
