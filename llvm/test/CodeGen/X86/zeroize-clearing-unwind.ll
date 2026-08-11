; A cleanup leaves the function by calling the routine that resumes unwinding.
; That block does not end in a return, so the walk over return blocks that
; register clearing used to do never reached it, and a function that unwound
; out of a cleanup left its registers to the unwinder. Driving the emission off
; the exit classification puts the sequence there.

; RUN: llc -mtriple=x86_64-unknown-linux-gnu %s -o - | FileCheck %s

declare void @sink()
declare i32 @__gxx_personality_v0(...)

define void @cleanup_resumes() "zero-call-used-regs"="used-gpr" personality ptr @__gxx_personality_v0 {
; The return is cleared as it always was: everything the function used, which
; here is the return of the call and the argument the calls were given.
; CHECK-LABEL: cleanup_resumes:
; CHECK:       # %bb.1:
; CHECK:       xorl %eax, %eax
; CHECK-NEXT:  xorl %edi, %edi
; CHECK-NEXT:  retq
;
; The cleanup is cleared too, and in front of the call rather than after it:
; there is no after. The exception object is in the argument register the
; resume call reads, so that register is left alone; clearing it would hand the
; unwinder nothing to resume with.
; CHECK:       .LBB0_2:
; CHECK:       movq %rbx, %rdi
; CHECK-NEXT:  xorl %eax, %eax
; CHECK-NEXT:  callq _Unwind_Resume
; CHECK-NOT:   xorl
entry:
  invoke void @sink() to label %cont unwind label %lpad

cont:
  ret void

lpad:
  %l = landingpad { ptr, i32 } cleanup
  call void @sink()
  resume { ptr, i32 } %l
}
