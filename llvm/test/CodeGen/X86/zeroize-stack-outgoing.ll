; RUN: llc -mtriple=x86_64-unknown-linux-gnu -verify-machineinstrs %s -o - \
; RUN:   | FileCheck %s --check-prefixes=CHECK,OPT
; RUN: llc -mtriple=x86_64-unknown-linux-gnu -O0 -verify-machineinstrs %s -o - \
; RUN:   | FileCheck %s --check-prefixes=CHECK,O0

; Outgoing arguments remain in the protected allocation until the exit clear.
declare void @many_arguments(i64, i64, i64, i64, i64, i64, i64, i64)
define void @outgoing_arguments() "zeroize-stack"="used" {
; CHECK-LABEL: outgoing_arguments:
; CHECK: callq many_arguments
; CHECK: movq $0, (%rsp)
; CHECK-NEXT: movq $0, 8(%rsp)
; CHECK-NEXT: movq $0, 16(%rsp)
; OPT-NEXT: addq $24, %rsp
; O0-NEXT: leaq 24(%rsp), %rsp
; CHECK-NEXT: .cfi_def_cfa %rsp, 8
; CHECK-NEXT: retq
  call void @many_arguments(i64 1, i64 2, i64 3, i64 4, i64 5, i64 6, i64 7, i64 8)
  ret void
}
