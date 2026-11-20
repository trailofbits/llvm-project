; RUN: llc -O0 -mtriple=x86_64-unknown-linux-gnu -mattr=+sahf -verify-machineinstrs %s -o %t
; RUN: FileCheck %s < %t
; RUN: FileCheck --check-prefix=CFI %s < %t
; RUN: llc -O2 -mtriple=x86_64-unknown-linux-gnu -mattr=+sahf -verify-machineinstrs %s -o - | FileCheck --check-prefix=SAVED %s
;
; A real landing pad reloads the exception object into RDI before resuming.
; The incoming RIP stays above the cleared 24-byte allocation, and the
; nested CALL pushes its own return address below it.
; CHECK-LABEL: explicit_cleanup:
; CHECK: subq $24, %rsp
; CHECK: .cfi_def_cfa_offset 32
; CHECK: callq may_throw
; CHECK: leaq 24(%rsp), %rsp
; CHECK: sahf
; CHECK: retq
; CHECK: callq clean
; CHECK: movq 8(%rsp), %rdi
; CHECK: movq $0, (%rsp)
; CHECK-NEXT: movq $0, 8(%rsp)
; CHECK-NEXT: movq $0, 16(%rsp)
; CHECK-NOT: %rdi
; CHECK-NOT: %rsp
; CHECK: testl %eax, %eax
; CHECK-NEXT: sahf
; CHECK-NEXT: callq _Unwind_Resume

; The normal return resets the CFA. The landing pad must re-establish the
; live frame rule and retain it through the final resume call.
; CFI-LABEL: explicit_cleanup:
; CFI: .cfi_def_cfa %rsp, 8
; CFI: retq
; CFI: .cfi_def_cfa_offset 32
; CFI-NOT: .cfi_
; CFI: callq _Unwind_Resume

; At -O2 RBX holds the ordinary result or the exception before clearing. The
; unwinder must see the original caller RBX once the push slot has been wiped.
; SAVED-LABEL: explicit_cleanup:
; SAVED: .cfi_offset %rbx, -16
; SAVED: callq may_throw
; SAVED: movq 16(%rsp), %rbx
; SAVED-NEXT: .cfi_restore %rbx
; SAVED-NEXT: movq $0, (%rsp)
; SAVED-NEXT: movq $0, 8(%rsp)
; SAVED-NEXT: movq $0, 16(%rsp)
; SAVED: .cfi_def_cfa %rsp, 8
; SAVED: retq
; SAVED: .cfi_def_cfa_offset 32
; SAVED-NEXT: .cfi_offset %rbx, -16
; SAVED: movq %rbx, %rdi
; SAVED-NEXT: movq 16(%rsp), %rbx
; SAVED-NEXT: .cfi_restore %rbx
; SAVED-NEXT: movq $0, (%rsp)
; SAVED-NEXT: movq $0, 8(%rsp)
; SAVED-NEXT: movq $0, 16(%rsp)
; SAVED-NOT: .cfi_
; SAVED-NOT: %rdi
; SAVED-NOT: %rsp
; SAVED: callq _Unwind_Resume

declare i32 @__gxx_personality_v0(...)
declare void @may_throw()
declare void @clean()
define i32 @explicit_cleanup(i32 %result) "zero-call-used-regs"="all" "zeroize-stack"="used" "zeroize-flags" personality ptr @__gxx_personality_v0 {
  %slot = alloca i32, align 4
  store volatile i32 42, ptr %slot
  invoke void @may_throw() to label %normal unwind label %cleanup
normal:
  ret i32 %result
cleanup:
  %exception = landingpad {ptr, i32} cleanup
  call void @clean()
  resume {ptr, i32} %exception
}
