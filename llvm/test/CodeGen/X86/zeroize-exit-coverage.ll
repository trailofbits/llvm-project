; Pin the classification of every exit shape a function can have on x86-64, at
; the point where clearing registers and the stack is enforced.
;
; The classification does not look at "zeroize-stack" or "zero-call-used-regs":
; which exits a function has is a property of the function, and the attributes
; only decide what is emitted at the ones that are in scope. None of the
; functions here carries one, so nothing is emitted and the classification is
; all there is to see.

; RUN: llc -mtriple=x86_64-unknown-linux-gnu -pei-print-exits %s -o /dev/null 2>&1 | FileCheck %s

; Off by default, and no diagnostics from any of this.
; RUN: llc -mtriple=x86_64-unknown-linux-gnu %s -o /dev/null 2>&1 | count 0

declare void @sink()
declare void @abort() noreturn
declare i32 @callee(i32)
declare void @llvm.trap()
declare void @llvm.eh.sjlj.longjmp(ptr)
declare i32 @__gxx_personality_v0(...)

; Every return is its own exit: the set of registers holding a live value
; differs between them, which is why one set computed for the whole function is
; not enough.
; CHECK-LABEL: exits for function 'two_returns':
; CHECK-NEXT:  %bb.1: return [in-scope]
; CHECK-NEXT:  %bb.2: return [in-scope]
; CHECK-NEXT:  end exits for function 'two_returns'
define i32 @two_returns(i32 %x) {
entry:
  %c = icmp sgt i32 %x, 0
  br i1 %c, label %pos, label %neg

pos:
  ret i32 1

neg:
  ret i32 2
}

; A tail call is a call marked as a return, so a walk over return blocks
; reaches it, but the frame is gone before the branch and the outgoing
; arguments are live across it. It is in scope, and giving it what it needs is
; trailofbits/vspells-ct-internal-notes#22.
; CHECK-LABEL: exits for function 'tail_call':
; CHECK-NEXT:  %bb.0: tail-call [in-scope]
; CHECK-NEXT:  end exits for function 'tail_call'
define i32 @tail_call(i32 %x) {
  %r = tail call i32 @callee(i32 %x)
  ret i32 %r
}

; A cleanup that only runs destructors ends in a call to the routine that
; resumes unwinding. The frame is still established there, so it is a place a
; clearing sequence can go: trailofbits/vspells-ct-internal-notes#25.
; CHECK-LABEL: exits for function 'cleanup_resumes':
; CHECK-NEXT:  %bb.1: return [in-scope]
; CHECK-NEXT:  %bb.2: unwind-resume [in-scope]
; CHECK-NEXT:  end exits for function 'cleanup_resumes'
define void @cleanup_resumes() personality ptr @__gxx_personality_v0 {
entry:
  invoke void @sink() to label %cont unwind label %lpad

cont:
  ret void

lpad:
  %l = landingpad { ptr, i32 } cleanup
  call void @sink()
  resume { ptr, i32 } %l
}

; A call that never comes back abandons the frame: the unwinder or the callee
; restores our caller, and nothing of ours runs in between. Out of scope.
; CHECK-LABEL: exits for function 'calls_noreturn':
; CHECK-NEXT:  %bb.0: no-return-call [out-of-scope]
; CHECK-NEXT:  end exits for function 'calls_noreturn'
define void @calls_noreturn() {
  call void @abort()
  unreachable
}

; A longjmp reloads the stack and frame pointers of another frame and jumps.
; Same abandoned frame, out of scope for the same reason.
; CHECK-LABEL: exits for function 'longjmps':
; CHECK-NEXT:  %bb.0: non-local-jump [out-of-scope]
; CHECK-NEXT:  end exits for function 'longjmps'
define void @longjmps(ptr %buf) {
  call void @llvm.eh.sjlj.longjmp(ptr %buf)
  unreachable
}

; A trap does not transfer out of the frame at all, so there is nothing to
; protect. It is still reported, so that a block reaching the end of the
; function is never silently unclassified.
; CHECK-LABEL: exits for function 'traps':
; CHECK-NEXT:  %bb.0: unreachable [out-of-scope]
; CHECK-NEXT:  end exits for function 'traps'
define void @traps() {
  call void @llvm.trap()
  unreachable
}

; An unreachable on its own leaves an empty block behind. Same again.
; CHECK-LABEL: exits for function 'unreachable_block':
; CHECK-NEXT:  %bb.1: return [in-scope]
; CHECK-NEXT:  %bb.2: unreachable [out-of-scope]
; CHECK-NEXT:  end exits for function 'unreachable_block'
define void @unreachable_block(i32 %x) {
entry:
  %c = icmp sgt i32 %x, 0
  br i1 %c, label %ok, label %bad

ok:
  ret void

bad:
  unreachable
}

; A block that only calls is not an exit: control comes back to it.
; CHECK-LABEL: exits for function 'call_is_not_an_exit':
; CHECK-NEXT:  %bb.0: return [in-scope]
; CHECK-NEXT:  end exits for function 'call_is_not_an_exit'
define void @call_is_not_an_exit() {
  call void @sink()
  ret void
}

; All of it in one function, to show the kinds are decided per exit and not
; per function.
; CHECK-LABEL: exits for function 'mixed':
; CHECK-NEXT:  %bb.2: return [in-scope]
; CHECK-NEXT:  %bb.3: no-return-call [out-of-scope]
; CHECK-NEXT:  %bb.4: tail-call [in-scope]
; CHECK-NEXT:  end exits for function 'mixed'
define i32 @mixed(i32 %x) {
entry:
  switch i32 %x, label %tail [
    i32 0, label %normal
    i32 1, label %die
  ]

normal:
  ret i32 0

die:
  call void @abort()
  unreachable

tail:
  %r = tail call i32 @callee(i32 %x)
  ret i32 %r
}
