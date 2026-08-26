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

; What the sequence clears is decided per exit, and for the x87 registers that
; shows in the count. They are not addressable by name, so clearing them means
; pushing a zero for each and popping it straight back off, and how many to push
; depends on what the exit leaves on the stack. A return handing back a long
; double leaves it in ST0; X86FrameLowering reads that off the implicit ST0 use
; the FP stackifier left on the return and pushes seven, so the eighth does not
; land on the value being returned. The resume call carries no such use and
; there is no returned value on the path that reaches it, so all eight are
; cleared. Eight pushes need the x87 stack empty, which it is at a call
; boundary: the long double is spilled to the frame before the invoke and
; reloaded only on the way to the return. Each count is closed off, the pops as
; well as the pushes: a pop with no push in front of it is what an x87 stack
; underflow looks like, and a lower bound would let one through.
define x86_fp80 @cleanup_resumes_x87(x86_fp80 %x) "zero-call-used-regs"="all" personality ptr @__gxx_personality_v0 {
; CHECK-LABEL: cleanup_resumes_x87:
; CHECK-COUNT-7: fldz
; CHECK-NOT:     fldz
; CHECK-COUNT-7: fstp %st(0)
; CHECK-NOT:     fstp %st(0)
; CHECK:         retq
;
; CHECK-COUNT-8: fldz
; CHECK-NOT:     fldz
; CHECK-COUNT-8: fstp %st(0)
; CHECK-NOT:     fstp %st(0)
; CHECK:         callq _Unwind_Resume
entry:
  invoke void @sink() to label %cont unwind label %lpad

cont:
  ret x86_fp80 %x

lpad:
  %l = landingpad { ptr, i32 } cleanup
  resume { ptr, i32 } %l
}
