; The register clear is what finishes the stack clear's work: it destroys the
; registers the stack clear read the frame through. A target that cannot clear
; registers therefore cannot clear the frame either, and has to say so rather
; than emit the half of the sequence it can do. ARM implements neither, so it
; is where that can be pinned.
;
; As in the X86 test, -pei-stack-clear-scratch-regs stands in for the step that
; clears the frame, which no target implements
; (trailofbits/vspells-ct-internal-notes#26).

; RUN: not llc -mtriple=armv7-unknown-linux-gnueabi -pei-stack-clear-scratch-regs=r4 < %s -o /dev/null 2>&1 | FileCheck %s

; The function asked for its frame to be cleared and said nothing about its
; registers, so the register clear it gets is one it did not ask for. It is
; still a register clear, and this target cannot do one, so the request to
; clear the frame cannot be discharged.
; CHECK: error: {{.*}}in function stack_only i32 (i32): clearing the stack needs the registers it uses to be cleared afterwards, which is not supported by this target
define i32 @stack_only(i32 %x) "zeroize-stack"="used" {
  ret i32 %x
}

; A function that did ask for its registers to be cleared is refused on its own
; terms, by the query that has always answered that request, rather than being
; refused twice or reported as something it did not ask for.
; CHECK: error: {{.*}}in function asked_for_both i32 (i32): "zero-call-used-regs" is not supported by this target
; CHECK-NOT: in function asked_for_both {{.*}}clearing the stack needs
define i32 @asked_for_both(i32 %x) "zeroize-stack"="used" "zero-call-used-regs"="used-gpr" {
  ret i32 %x
}

; A function that asked for neither is not dragged into any of this.
; CHECK-NOT: in function untouched
define i32 @untouched(i32 %x) {
  ret i32 %x
}
