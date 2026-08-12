; Clearing the stack frame needs registers to do it with, and leaves them
; holding what it took out of the frame. The register clear runs after it for
; that reason, but running after is not the same as covering: what the register
; clear covers is chosen by "zero-call-used-regs", and no mode selects a
; register the clearing machinery itself dirtied. So a step declares the
; registers it used and the register clear adds them to what it clears.
;
; No target clears the stack yet (trailofbits/vspells-ct-internal-notes#26), so
; the step that would declare anything declares nothing, and there is no
; producer to exercise this with. -pei-stack-clear-scratch-regs stands in for
; one. What that leaves demonstrable is one thing, and it is what is tested
; here: a register declared by a step in front of the register clear is cleared
; by it, in cases where nothing else would have cleared it. The registers a
; real stack clear picks, and the code that picks them, are not tested here
; because they do not exist yet.

; RUN: llc -mtriple=x86_64-unknown-linux-gnu -pei-stack-clear-scratch-regs=r11 < %s | FileCheck %s
; RUN: llc -mtriple=x86_64-unknown-linux-gnu -pei-stack-clear-scratch-regs=r11 -pei-print-clearing-sequence < %s -o /dev/null 2>&1 | FileCheck %s --check-prefix=SEQ

declare i32 @callee(i32)

; %r11 is not a register this function uses, so "used-gpr" does not select it
; and the register clear would not have touched it. It is cleared because the
; step in front declared it. What the mode does select is still cleared, and
; what the exit needs is still spared: %eax carries the return value out.
; CHECK-LABEL: declared_reaches_the_clear:
; CHECK:         movl %edi, %eax
; CHECK-NEXT:    xorl %edi, %edi
; CHECK-NEXT:    xorl %r11d, %r11d
; CHECK-NEXT:    retq
define i32 @declared_reaches_the_clear(i32 %x) "zeroize-stack"="used" "zero-call-used-regs"="used-gpr" {
  ret i32 %x
}

; A function that asked for its frame to be cleared and said nothing about its
; registers still gets a register clear, over nothing but what was declared.
; Asking for the frame to be cleared and leaving its contents in a register is
; not a way of discharging the request.
; CHECK-LABEL: no_register_request:
; CHECK:         movl %edi, %eax
; CHECK-NEXT:    xorl %r11d, %r11d
; CHECK-NEXT:    retq
define i32 @no_register_request(i32 %x) "zeroize-stack"="used" {
  ret i32 %x
}

; The same when the function asked for no register clear in so many words.
; "skip" declines a clear of what the function left in its registers; it says
; nothing about what clearing its frame put there, which is not the function's
; doing. %edi is left alone, which is what "skip" does mean.
; CHECK-LABEL: skip_is_still_covered:
; CHECK:         movl %edi, %eax
; CHECK-NEXT:    xorl %r11d, %r11d
; CHECK-NEXT:    retq
define i32 @skip_is_still_covered(i32 %x) "zeroize-stack"="used" "zero-call-used-regs"="skip" {
  ret i32 %x
}

; The declaration is made and consumed at each exit, not once for the function,
; so every in-scope exit covers what the step used there.
; CHECK-LABEL: every_exit:
; CHECK:         movl $1, %eax
; CHECK-NEXT:    xorl %r11d, %r11d
; CHECK-NEXT:    retq
; CHECK:         movl $2, %eax
; CHECK-NEXT:    xorl %r11d, %r11d
; CHECK-NEXT:    retq
define i32 @every_exit(i32 %x) "zeroize-stack"="used" {
entry:
  %c = icmp sgt i32 %x, 0
  br i1 %c, label %pos, label %neg

pos:
  ret i32 1

neg:
  ret i32 2
}

; Nothing declares anything in a function whose frame is not being cleared, so
; the register clear covers what its mode selects and no more. This is the
; control for the tests above: without it they would pass just as well if the
; register clear had started clearing %r11 for some unrelated reason.
; CHECK-LABEL: no_stack_clear:
; CHECK:         movl %edi, %eax
; CHECK-NEXT:    xorl %edi, %edi
; CHECK-NEXT:    retq
; CHECK-NOT:     %r11d
define i32 @no_stack_clear(i32 %x) "zero-call-used-regs"="used-gpr" {
  ret i32 %x
}

; The sequence reports what was declared at each exit, so the declaration is
; visible without reading the registers back out of the emitted code.
; SEQ-LABEL: clearing sequence for function 'declared_reaches_the_clear':
; SEQ-NEXT:    %bb.0 return: clear-stack=emitted clear-registers=emitted clear-flags=unimplemented scratch=R11
; SEQ-LABEL: clearing sequence for function 'no_register_request':
; SEQ-NEXT:    %bb.0 return: clear-stack=emitted clear-registers=emitted clear-flags=unimplemented scratch=R11
; SEQ-LABEL: clearing sequence for function 'every_exit':
; SEQ-NEXT:    %bb.1 return: clear-stack=emitted clear-registers=emitted clear-flags=unimplemented scratch=R11
; SEQ-NEXT:    %bb.2 return: clear-stack=emitted clear-registers=emitted clear-flags=unimplemented scratch=R11
; SEQ-LABEL: clearing sequence for function 'no_stack_clear':
; SEQ-NEXT:    %bb.0 return: clear-stack=not-requested clear-registers=emitted clear-flags=unimplemented
