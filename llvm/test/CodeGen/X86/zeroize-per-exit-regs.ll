; The registers a clearing sequence can destroy are the ones dead where it
; runs, and which ones those are is a property of the exit it runs at. The set
; used to be computed once for the function, with the registers every return
; needed taken out of it, so each exit was denied every other exit's live-out
; registers and left them holding whatever the function had put in them. It is
; computed per exit now.

; RUN: llc -mtriple=x86_64-unknown-linux-gnu %s -o - | FileCheck %s

declare i32 @callee(i32, i32)
declare void @sink()
declare i32 @__gxx_personality_v0(...)

; Two returns that need different registers. The union of what they need is
; every register the function uses, so the function-wide set was empty and
; neither exit cleared anything at all:
;
;   .LBB0_2:                # %tail
;           movl %esi, %edi
;           movl %edx, %esi
;           jmp callee@PLT  # TAILCALL
;   .LBB0_1:                # %plain
;           addl %edx, %esi
;           movl %esi, %eax
;           retq
;
; Neither exit needs all of them. The tail call needs the outgoing arguments in
; %edi and %esi and does not need %eax, which the callee is about to write; the
; return needs the return value in %eax and does not need %edi, %esi or %edx,
; which nothing reads after it. Each exit now clears what the other one needed.
define i32 @tail_and_return(i1 %c, i32 %a, i32 %b) "zero-call-used-regs"="used-gpr" {
; CHECK-LABEL: tail_and_return:
;
; CHECK:       # %bb.2:
; CHECK:         movl %esi, %edi
; CHECK-NEXT:    movl %edx, %esi
; CHECK-NEXT:    xorl %eax, %eax
; CHECK-NEXT:    jmp callee@PLT
;
; CHECK:       .LBB0_1:
; CHECK:         movl %esi, %eax
; CHECK-NEXT:    xorl %edi, %edi
; CHECK-NEXT:    xorl %edx, %edx
; CHECK-NEXT:    xorl %esi, %esi
; CHECK-NEXT:    retq
entry:
  br i1 %c, label %tail, label %plain

tail:
  %r = tail call i32 @callee(i32 %a, i32 %b)
  ret i32 %r

plain:
  %s = add i32 %a, %b
  ret i32 %s
}

; The same contrast between a return and an exit that resumes unwinding. The
; return leaves the result in %eax, so the function-wide set had %eax taken out
; of it and the resume exit did not clear it either, although nothing on that
; path had put a return value there and nothing on it reads one. What the
; resume exit does need, the exception object in %rdi, it still keeps: that is
; the exit's own answer rather than another exit's.
define i32 @cleanup_and_return(i32 %secret) "zero-call-used-regs"="used-gpr" personality ptr @__gxx_personality_v0 {
; CHECK-LABEL: cleanup_and_return:
;
; The return exit is unchanged: %eax carries the result out and %edi is dead.
; CHECK:       # %bb.1:
; CHECK:         movl %ebx, %eax
; CHECK:         xorl %edi, %edi
; CHECK-NEXT:    retq
;
; CHECK:       .LBB1_2:
; CHECK:         movq %rax, %rdi
; CHECK-NEXT:    xorl %eax, %eax
; CHECK-NEXT:    callq _Unwind_Resume
; CHECK-NOT:     xorl
entry:
  invoke void @sink() to label %cont unwind label %lpad

cont:
  ret i32 %secret

lpad:
  %l = landingpad { ptr, i32 } cleanup
  resume { ptr, i32 } %l
}

; A function with one exit has nothing to take a union over, so the per-exit
; set is the set that was computed for the function and what "used-gpr" emits
; is what it emitted before. Every mode's meaning is a statement about the
; function, and none of them changes here; only the exclusion moves.
define i32 @one_return(i32 %a, i32 %b) "zero-call-used-regs"="used-gpr" {
; CHECK-LABEL: one_return:
; CHECK:         leal (%rdi,%rsi), %eax
; CHECK-NEXT:    xorl %edi, %edi
; CHECK-NEXT:    xorl %esi, %esi
; CHECK-NEXT:    retq
  %s = add i32 %a, %b
  ret i32 %s
}
