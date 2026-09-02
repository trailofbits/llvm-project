; The register clear is what finishes the stack clear's work: it destroys the
; registers the stack clear read the frame through. So a function that asked
; only for its frame to be cleared gets a register clear it did not ask for,
; covering exactly the registers the stack clear used.
;
; As in the X86 test, -pei-stack-clear-scratch-regs stands in for the step that
; clears the frame, which no target implements
; (trailofbits/vspells-ct-internal-notes#26).
;
; The register named has to be one the exit does not need. r4 would not do:
; it is callee-saved under AAPCS, and a step may not declare as scratch a
; register whose value at the exit something depends on. r12 is the call-used
; register with no role at a return, which is what %r11 is in the X86 test.

; RUN: llc -mtriple=armv7-unknown-linux-gnueabi -pei-stack-clear-scratch-regs=r12 < %s | FileCheck %s
; RUN: llc -mtriple=armv7-unknown-linux-gnueabi -pei-stack-clear-scratch-regs=r12 -pei-print-clearing-sequence < %s -o /dev/null 2>&1 | FileCheck %s --check-prefix=SEQ

; This function said nothing about its registers. The clear it gets is the one
; the stack clear needs, and it covers the declared scratch and nothing else.
; CHECK-LABEL: stack_only:
; CHECK:         mov r12, #0
; CHECK-NEXT:    bx lr
; SEQ-LABEL: clearing sequence for function 'stack_only':
; SEQ-NEXT:   %bb.0 return: clear-stack=emitted clear-registers=emitted clear-flags=unimplemented scratch=R12
define i32 @stack_only(i32 %x) "zeroize-stack"="used" {
  ret i32 %x
}

; A function that did ask for its registers to be cleared gets one clear, not
; two: the scratch the stack clear declared joins the set the request already
; named rather than being cleared separately.
; CHECK-LABEL: asked_for_both:
; CHECK:         mov r12, #0
; CHECK-NEXT:    bx lr
; SEQ-LABEL: clearing sequence for function 'asked_for_both':
; SEQ-NEXT:   %bb.0 return: clear-stack=emitted clear-registers=emitted clear-flags=unimplemented scratch=R12
define i32 @asked_for_both(i32 %x) "zeroize-stack"="used" "zero-call-used-regs"="used-gpr" {
  ret i32 %x
}

; A function that asked for neither is not dragged into any of this.
; CHECK-LABEL: untouched:
; CHECK-NOT:     mov r12, #0
; CHECK:         bx lr
; SEQ-LABEL: clearing sequence for function 'untouched':
; SEQ-NEXT:   %bb.0 return: clear-stack=not-requested clear-registers=not-requested clear-flags=unimplemented
define i32 @untouched(i32 %x) {
  ret i32 %x
}
