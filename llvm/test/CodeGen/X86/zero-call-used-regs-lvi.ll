; RUN: llc -mtriple=x86_64-unknown-linux-gnu -mattr=+lvi-cfi -O0 -verify-machineinstrs < %s | FileCheck %s
; RUN: llc -mtriple=x86_64-unknown-linux-gnu -mattr=+lvi-cfi -O2 -verify-machineinstrs < %s | FileCheck %s
; RUN: llc -mtriple=x86_64-unknown-linux-gnu -mattr=+lvi-cfi,+lvi-load-hardening -O0 -verify-machineinstrs < %s | FileCheck %s
; RUN: llc -mtriple=x86_64-unknown-linux-gnu -mattr=+lvi-cfi,+lvi-load-hardening -O2 -verify-machineinstrs < %s | FileCheck %s

; Clearing bookkeeping must not force LVI's no-scratch fallback.
define void @clear_all_gpr() "zero-call-used-regs"="all-gpr" {
; CHECK-LABEL: clear_all_gpr:
; CHECK-DAG: xorl %eax, %eax
; CHECK-DAG: xorl %ecx, %ecx
; CHECK-DAG: xorl %edi, %edi
; CHECK-DAG: xorl %edx, %edx
; CHECK-DAG: xorl %esi, %esi
; CHECK-DAG: xorl %r8d, %r8d
; CHECK-DAG: xorl %r9d, %r9d
; CHECK-DAG: xorl %r10d, %r10d
; CHECK-DAG: xorl %r11d, %r11d
; CHECK: popq %rax
; CHECK-NEXT: lfence
; CHECK-NEXT: jmpq *%rax
  ret void
}

define void @clear_all() "zero-call-used-regs"="all" {
; CHECK-LABEL: clear_all:
; CHECK: xorps %xmm0, %xmm0
; CHECK: popq %rax
; CHECK-NEXT: lfence
; CHECK-NEXT: jmpq *%rax
  ret void
}

define i64 @return_integer(i64 %x) "zero-call-used-regs"="all-gpr" {
; CHECK-LABEL: return_integer:
; CHECK: movq %rdi, %rax
; CHECK-NOT: xorl %eax, %eax
; CHECK: xorl %ecx, %ecx
; CHECK-NOT: xorl %eax, %eax
; CHECK: popq %rcx
; CHECK-NEXT: lfence
; CHECK-NEXT: jmpq *%rcx
  ret i64 %x
}

; A subregister return still makes its full register unavailable as scratch.
define i8 @return_byte(i32 %x) "zero-call-used-regs"="all-gpr" {
; CHECK-LABEL: return_byte:
; CHECK-NOT: xorl %eax, %eax
; CHECK: popq %rcx
; CHECK-NEXT: lfence
; CHECK-NEXT: jmpq *%rcx
  %r = trunc i32 %x to i8
  ret i8 %r
}

define i128 @return_pair(i128 %x) "zero-call-used-regs"="all-gpr" {
; CHECK-LABEL: return_pair:
; CHECK-DAG: movq %rdi, %rax
; CHECK-DAG: movq %rsi, %rdx
; CHECK-NOT: xorl %eax, %eax
; CHECK-NOT: xorl %edx, %edx
; CHECK: popq %rcx
; CHECK-NEXT: lfence
; CHECK-NEXT: jmpq *%rcx
  ret i128 %x
}
