; RUN: llc -O2 -mtriple=x86_64-unknown-linux-gnu -mattr=+sahf -verify-machineinstrs %s -o - | FileCheck %s
;
; The vector lives across several calls and therefore has a register allocator
; spill. Its reload and the caller-owned results must precede the frame clear.

; CHECK-LABEL: spill_cleanup:
; CHECK: .cfi_def_cfa_offset 176
; CHECK: movaps %xmm0, (%rsp)
; CHECK: callq may_throw
; CHECK: movaps (%rsp), %xmm0
; CHECK: callq finish
; CHECK: movq 136(%rsp), %rbx
; CHECK-NEXT: .cfi_restore %rbx
; CHECK-NEXT: movq 144(%rsp), %r14
; CHECK-NEXT: .cfi_restore %r14
; CHECK-NEXT: movq 152(%rsp), %r15
; CHECK-NEXT: .cfi_restore %r15
; CHECK-NEXT: movq 160(%rsp), %rbp
; CHECK-NEXT: .cfi_restore %rbp
; CHECK-NEXT: leaq (%rsp), %r11
; CHECK-NEXT: movq $168, %r10
; CHECK: [[RETLOOP:\.LBB[0-9_]+]]:
; CHECK: movq $0, (%r11)
; CHECK-NEXT: addq $8, %r11
; CHECK-NEXT: subq $8, %r10
; CHECK-NEXT: jne [[RETLOOP]]
; CHECK: addq $168, %rsp
; CHECK-NEXT: .cfi_def_cfa %rsp, 8
; CHECK: retq
; CHECK: .cfi_def_cfa_offset 176
; CHECK-DAG: .cfi_offset %rbx, -40
; CHECK-DAG: .cfi_offset %rbp, -16
; CHECK-DAG: .cfi_offset %r14, -32
; CHECK-DAG: .cfi_offset %r15, -24
; CHECK: movq %rbx, %rdi
; CHECK-NEXT: movq 136(%rsp), %rbx
; CHECK-NEXT: .cfi_restore %rbx
; CHECK-NEXT: movq 144(%rsp), %r14
; CHECK-NEXT: .cfi_restore %r14
; CHECK-NEXT: movq 152(%rsp), %r15
; CHECK-NEXT: .cfi_restore %r15
; CHECK-NEXT: movq 160(%rsp), %rbp
; CHECK-NEXT: .cfi_restore %rbp
; CHECK-NEXT: leaq (%rsp), %r11
; CHECK-NEXT: movq $168, %r10
; CHECK: [[RESUMELOOP:\.LBB[0-9_]+]]:
; CHECK: movq $0, (%r11)
; CHECK-NEXT: addq $8, %r11
; CHECK-NEXT: subq $8, %r10
; CHECK-NEXT: jne [[RESUMELOOP]]
; CHECK-NOT: .cfi_
; CHECK-NOT: %rsp
; CHECK-NOT: %rdi
; CHECK: testl %eax, %eax
; CHECK-NEXT: sahf
; CHECK-NEXT: callq _Unwind_Resume

declare i32 @__gxx_personality_v0(...)
declare void @prepare_array(ptr, i32) nounwind
declare <4 x i32> @vector_for(i32) nounwind
declare i32 @source(i32, i32) nounwind
declare void @may_throw(i32)
declare i32 @finish(<4 x i32>, ptr, i32, i32, i32) nounwind
declare void @destroyed() nounwind

define i32 @spill_cleanup(i32 %value) uwtable "zero-call-used-regs"="all" "zeroize-stack"="used" "zeroize-flags" personality ptr @__gxx_personality_v0 {
entry:
  %array = alloca [28 x i32], align 16
  call void @prepare_array(ptr %array, i32 %value)
  %vec = call <4 x i32> @vector_for(i32 %value)
  %a = call i32 @source(i32 %value, i32 1)
  %b = call i32 @source(i32 %value, i32 2)
  %c = call i32 @source(i32 %value, i32 3)
  invoke void @may_throw(i32 %value) to label %normal unwind label %cleanup
normal:
  %result = call i32 @finish(<4 x i32> %vec, ptr %array, i32 %a, i32 %b, i32 %c)
  call void @destroyed()
  ret i32 %result
cleanup:
  %exception = landingpad {ptr, i32} cleanup
  call void @destroyed()
  resume {ptr, i32} %exception
}
