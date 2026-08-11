; The classification is not written in terms of any one target's instructions.
; The resume routine in particular is asked for by libcall, so under the ARM EH
; ABI a cleanup that ends in __cxa_end_cleanup is recognised for the same
; reason an x86-64 cleanup ending in _Unwind_Resume is.

; RUN: llc -mtriple=armv7-unknown-linux-gnueabihf -pei-print-exits %s -o /dev/null 2>&1 | FileCheck %s

declare void @sink()
declare i32 @callee(i32)
declare void @llvm.eh.sjlj.longjmp(ptr)
declare i32 @__gxx_personality_v0(...)

; CHECK-LABEL: exits for function 'plain_return':
; CHECK-NEXT:  %bb.0: return [in-scope]
; CHECK-NEXT:  end exits for function 'plain_return'
define i32 @plain_return(i32 %x) {
  ret i32 %x
}

; CHECK-LABEL: exits for function 'tail_call':
; CHECK-NEXT:  %bb.0: tail-call [in-scope]
; CHECK-NEXT:  end exits for function 'tail_call'
define i32 @tail_call(i32 %x) {
  %r = tail call i32 @callee(i32 %x)
  ret i32 %r
}

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

; ARM spells a longjmp as a barrier pseudo rather than as an indirect branch,
; and it classifies the same way.
; CHECK-LABEL: exits for function 'longjmps':
; CHECK-NEXT:  %bb.0: non-local-jump [out-of-scope]
; CHECK-NEXT:  end exits for function 'longjmps'
define void @longjmps(ptr %buf) {
  call void @llvm.eh.sjlj.longjmp(ptr %buf)
  unreachable
}
