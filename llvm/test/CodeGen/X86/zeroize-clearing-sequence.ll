; What is emitted at an exit is one ordered sequence of named steps, run at the
; exits the classification calls in scope. Pin both: the order the steps are
; run in, and the exits the sequence is run at.

; RUN: llc -mtriple=x86_64-unknown-linux-gnu -pei-print-clearing-sequence %s -o /dev/null 2>&1 | FileCheck %s

; The flag is the only thing that shows the sequence; it is off by default, and
; none of this reports anything.
; RUN: llc -mtriple=x86_64-unknown-linux-gnu %s -o /dev/null 2>&1 | count 0

declare void @sink()
declare void @abort() noreturn
declare i32 @callee(i32)
declare void @llvm.trap()
declare void @llvm.eh.sjlj.longjmp(ptr)
declare i32 @__gxx_personality_v0(...)

; The order is clear-stack, then clear-registers, then clear-flags, and it is
; the same at every exit: the stack clear needs registers to run and so has to
; be in front of the register clear, and every step writes the flags so the
; flag clear has to be behind all of them.
; CHECK-LABEL: clearing sequence for function 'one_return':
; CHECK-NEXT:  %bb.0 return: clear-stack=not-requested clear-registers=emitted clear-flags=unimplemented
; CHECK-NEXT:  end clearing sequence for function 'one_return'
define i32 @one_return(i32 %x) "zero-call-used-regs"="used-gpr" {
  ret i32 %x
}

; The steps a function does not ask for hold their positions anyway: which
; steps run is a property of the function, the order is not.
; CHECK-LABEL: clearing sequence for function 'asks_for_nothing':
; CHECK-NEXT:  %bb.0 return: clear-stack=not-requested clear-registers=not-requested clear-flags=unimplemented
; CHECK-NEXT:  end clearing sequence for function 'asks_for_nothing'
define i32 @asks_for_nothing(i32 %x) {
  ret i32 %x
}

; Every in-scope exit gets the sequence, not one of them and not the first.
; CHECK-LABEL: clearing sequence for function 'two_returns':
; CHECK-NEXT:  %bb.1 return: clear-stack=not-requested clear-registers=emitted clear-flags=unimplemented
; CHECK-NEXT:  %bb.2 return: clear-stack=not-requested clear-registers=emitted clear-flags=unimplemented
; CHECK-NEXT:  end clearing sequence for function 'two_returns'
define i32 @two_returns(i32 %x) "zero-call-used-regs"="used-gpr" {
entry:
  %c = icmp sgt i32 %x, 0
  br i1 %c, label %pos, label %neg

pos:
  ret i32 1

neg:
  ret i32 2
}

; A cleanup that leaves by calling the routine that resumes unwinding is an
; exit, and it is not a block that ends in a return, so a walk over return
; blocks never reached it. The sequence runs there because the classification
; says it is in scope.
; CHECK-LABEL: clearing sequence for function 'cleanup_resumes':
; CHECK-NEXT:  %bb.1 return: clear-stack=not-requested clear-registers=emitted clear-flags=unimplemented
; CHECK-NEXT:  %bb.2 unwind-resume: clear-stack=not-requested clear-registers=emitted clear-flags=unimplemented
; CHECK-NEXT:  end clearing sequence for function 'cleanup_resumes'
define void @cleanup_resumes() "zero-call-used-regs"="used-gpr" personality ptr @__gxx_personality_v0 {
entry:
  invoke void @sink() to label %cont unwind label %lpad

cont:
  ret void

lpad:
  %l = landingpad { ptr, i32 } cleanup
  call void @sink()
  resume { ptr, i32 } %l
}

; A tail call is in scope, and stays in scope. What a tail call needs beyond
; being reached is left for a later change; this pins only that the exit is
; classified and that the sequence runs at it.
; CHECK-LABEL: clearing sequence for function 'tail_call':
; CHECK-NEXT:  %bb.0 tail-call: clear-stack=not-requested clear-registers=emitted clear-flags=unimplemented
; CHECK-NEXT:  end clearing sequence for function 'tail_call'
define i32 @tail_call(i32 %x) "zero-call-used-regs"="used-gpr" {
  %r = tail call i32 @callee(i32 %x)
  ret i32 %r
}

; The exits that abandon the frame rather than release it get nothing, and the
; list is pinned between the two lines that bracket it, so an out-of-scope exit
; that started being emitted at would show up here.
; CHECK-LABEL: clearing sequence for function 'out_of_scope_exits':
; CHECK-NEXT:  %bb.3 return: clear-stack=not-requested clear-registers=emitted clear-flags=unimplemented
; CHECK-NEXT:  end clearing sequence for function 'out_of_scope_exits'
define void @out_of_scope_exits(i32 %x, ptr %buf) "zero-call-used-regs"="used-gpr" {
entry:
  switch i32 %x, label %jump [
    i32 0, label %normal
    i32 1, label %die
    i32 2, label %crash
  ]

normal:
  ret void

die:
  call void @abort()
  unreachable

crash:
  call void @llvm.trap()
  unreachable

jump:
  call void @llvm.eh.sjlj.longjmp(ptr %buf)
  unreachable
}
