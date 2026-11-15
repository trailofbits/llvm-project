; RUN: llc -mtriple=x86_64-unknown-linux-gnu -mattr=+sahf \
; RUN:   -verify-machineinstrs %s -o - | FileCheck %s
; RUN: llc -mtriple=x86_64-unknown-linux-gnu -mattr=+sahf -O0 \
; RUN:   -verify-machineinstrs %s -o - | FileCheck %s
; RUN: llc -mtriple=x86_64-unknown-linux-gnu -mattr=+sahf -filetype=obj %s -o /dev/null

; SAHF does not write OF, so TEST must survive before it.
define void @void_return() "zeroize-flags" {
; CHECK-LABEL: void_return:
; CHECK: xorl %eax, %eax
; CHECK-NEXT: testl %eax, %eax
; CHECK-NEXT: sahf
; CHECK-NEXT: retq
  ret void
}

; Borrow RAX without spilling and leave the borrowed scratch register zero.
define i64 @integer_return(i64 %x) "zeroize-flags" {
; CHECK-LABEL: integer_return:
; CHECK: xorl %r11d, %r11d
; CHECK-NEXT: xchgq %r11, %rax
; CHECK-NEXT: testl %eax, %eax
; CHECK-NEXT: sahf
; CHECK-NEXT: xchgq %r11, %rax
; CHECK-NEXT: retq
  ret i64 %x
}

define i128 @wide_return(i128 %x) "zeroize-flags" {
; CHECK-LABEL: wide_return:
; CHECK: xchgq %r11, %rax
; CHECK-NEXT: testl %eax, %eax
; CHECK-NEXT: sahf
; CHECK-NEXT: xchgq %r11, %rax
; CHECK-NEXT: retq
  ret i128 %x
}

define double @vector_return(double %x) "zeroize-flags" {
; CHECK-LABEL: vector_return:
; CHECK: xorl %eax, %eax
; CHECK-NEXT: testl %eax, %eax
; CHECK-NEXT: sahf
; CHECK-NEXT: retq
  ret double %x
}

define void @registers_then_flags() "zero-call-used-regs"="all-gpr" "zeroize-flags" {
; CHECK-LABEL: registers_then_flags:
; CHECK: xorl %r11d, %r11d
; CHECK-NEXT: testl %eax, %eax
; CHECK-NEXT: sahf
; CHECK-NEXT: retq
  ret void
}

declare i64 @callee(i64)
define i64 @suppress_tail(i64 %x) "zeroize-flags" {
; CHECK-LABEL: suppress_tail:
; CHECK: callq callee
; CHECK: sahf
; CHECK: retq
  %r = tail call i64 @callee(i64 %x)
  ret i64 %r
}
