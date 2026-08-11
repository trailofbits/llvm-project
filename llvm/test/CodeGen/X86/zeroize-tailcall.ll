; A tail call replaces the caller's frame with the callee's and jumps, so
; control never comes back to the caller. A function carrying "zeroize-stack"
; has undertaken to clear its frame before it returns, and there is no point
; left at which it can do that once it has jumped away. Tail-call optimization
; is suppressed for a protected function; a function that never asked for the
; undertaking keeps it.

; RUN: not llc -mtriple=x86_64-unknown-linux-gnu %s -o - 2>/dev/null | FileCheck %s
; RUN: not llc -mtriple=x86_64-unknown-linux-gnu -pei-print-clearing-sequence %s -o /dev/null 2>&1 | FileCheck %s --check-prefix=EXITS

; Every "zeroize-stack" function below also reports that no target clears the
; frame yet, which is what the `not` is for. Those reports are what
; zeroize-stack-unsupported.ll is about and are discarded here.

declare i32 @callee(i32)
declare tailcc i32 @tcallee(i32)

; The call is marked `tail` and is in tail position, so it would be turned into
; a jump. It stays a call, and the function returns through its own epilogue.
; CHECK-LABEL: protected:
; CHECK-NOT:     TAILCALL
; CHECK:         callq callee@PLT
; CHECK:         retq
define i32 @protected(i32 %x) "zeroize-stack"="used" {
  %r = tail call i32 @callee(i32 %x)
  ret i32 %r
}

; The same body without the attribute. Nothing about the suppression is about
; the call, so this one is still a jump.
; CHECK-LABEL: unprotected:
; CHECK:         jmp callee@PLT # TAILCALL
define i32 @unprotected(i32 %x) {
  %r = tail call i32 @callee(i32 %x)
  ret i32 %r
}

; tailcc exists to guarantee the optimization rather than to permit it, and the
; guarantee is over the frame the protected function is undertaking to clear.
; The suppression covers it too, so a protected function does not get the
; guarantee by choosing the convention.
; CHECK-LABEL: protected_tailcc:
; CHECK-NOT:     TAILCALL
; CHECK:         callq tcallee@PLT
define tailcc i32 @protected_tailcc(i32 %x) "zeroize-stack"="used" {
  %r = tail call tailcc i32 @tcallee(i32 %x)
  ret i32 %r
}

; A libcall the legalizer generates has no call in the IR behind it, so it is
; not reached by the decision the other cases go through. It replaces the frame
; in exactly the same way, and is refused at the second place the tail-call
; question is asked.
; CHECK-LABEL: protected_libcall:
; CHECK-NOT:     TAILCALL
; CHECK:         callq fmod@PLT
; CHECK:         retq
define double @protected_libcall(double %a, double %b) "zeroize-stack"="used" {
  %r = frem double %a, %b
  ret double %r
}

; CHECK-LABEL: unprotected_libcall:
; CHECK:         jmp fmod@PLT # TAILCALL
define double @unprotected_libcall(double %a, double %b) {
  %r = frem double %a, %b
  ret double %r
}

; What the suppression does to the exits, which is where it meets the per-exit
; register clearing. Without the attribute the function has a tail-call exit and
; a return exit, and the clearing at each of them is computed for that exit.
; EXITS-LABEL: clearing sequence for function 'regs_unprotected':
; EXITS-NEXT:  %bb.1 tail-call: clear-stack=not-requested clear-registers=emitted clear-flags=unimplemented
; EXITS-NEXT:  %bb.2 return: clear-stack=not-requested clear-registers=emitted clear-flags=unimplemented
define i32 @regs_unprotected(i1 %c, i32 %a, i32 %b) "zero-call-used-regs"="used-gpr" {
entry:
  br i1 %c, label %tail, label %plain
tail:
  %r = tail call i32 @callee(i32 %a)
  ret i32 %r
plain:
  %s = add i32 %a, %b
  ret i32 %s
}

; The same function protected. The tail-call exit is gone: both exits are
; returns, and the register clearing at what used to be the tail call is now
; computed for a return. The two mechanisms do not overlap for a protected
; function, because it no longer has the exit the tail-call case was about.
; EXITS-LABEL: clearing sequence for function 'regs_protected':
; EXITS-NEXT:  %bb.1 return: clear-stack=unsupported clear-registers=emitted clear-flags=unimplemented
; EXITS-NEXT:  %bb.2 return: clear-stack=unsupported clear-registers=emitted clear-flags=unimplemented
define i32 @regs_protected(i1 %c, i32 %a, i32 %b) "zero-call-used-regs"="used-gpr" "zeroize-stack"="used" {
entry:
  br i1 %c, label %tail, label %plain
tail:
  %r = tail call i32 @callee(i32 %a)
  ret i32 %r
plain:
  %s = add i32 %a, %b
  ret i32 %s
}
