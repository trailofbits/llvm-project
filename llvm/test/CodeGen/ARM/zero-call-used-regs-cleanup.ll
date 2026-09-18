; RUN: llc -mtriple=armv7-none-eabi -verify-machineinstrs %s -o - | FileCheck %s
; RUN: llc -mtriple=thumbv7m-none-eabi -verify-machineinstrs %s -o - | FileCheck %s
; RUN: llc -mtriple=thumbv6m-none-eabi -verify-machineinstrs %s -o - | FileCheck %s

declare void @sink()
declare void @cleanup()
declare i32 @__gxx_personality_v0(...)
declare void @_Unwind_Resume(ptr) noreturn

; Both the ordinary return and ARM EHABI's cleanup exit need clearing. The
; latter must run before __cxa_end_cleanup rather than at the end of its block.
; CHECK-LABEL: cleanup_and_return:
; CHECK: mov{{.*}} r12,
; CHECK: {{(pop|ldm)}}
; CHECK: bl cleanup
; CHECK: mov{{.*}} r12,
; CHECK-NEXT: bl __cxa_end_cleanup
define i32 @cleanup_and_return(i32 %secret) "zero-call-used-regs"="all-gpr" personality ptr @__gxx_personality_v0 {
entry:
  invoke void @sink() to label %cont unwind label %lpad
cont:
  ret i32 %secret
lpad:
  %l = landingpad { ptr, i32 } cleanup
  call void @cleanup()
  resume { ptr, i32 } %l
}

; _Unwind_Resume consumes the exception object in r0. This direct call also
; tests the other cleanup routine understood by the shared coordinator.
; CHECK-LABEL: resume_call:
; CHECK-NOT: mov{{.*}} r0,
; CHECK: mov{{.*}} r12,
; CHECK-NOT: mov{{.*}} r0,
; CHECK-NEXT: bl _Unwind_Resume
define void @resume_call(ptr %exception) "zero-call-used-regs"="all-gpr" {
  call void @_Unwind_Resume(ptr %exception)
  unreachable
}

; LR can be absent from the callee-saved list and from the return's explicit
; operands. It is still the return address and must never be cleared.
; CHECK-LABEL: ghc_return:
; CHECK-NOT: mov{{.*}} lr,
; CHECK: mov{{.*}} r12,
; CHECK-NOT: mov{{.*}} lr,
; CHECK: bx lr
define ghccc void @ghc_return() "zero-call-used-regs"="all-gpr" {
  ret void
}
