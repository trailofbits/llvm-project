; RUN: llc -mtriple=armv7-none-eabi -pei-stack-clear-scratch-regs=r12 -verify-machineinstrs %s -o - | FileCheck %s
;
; An explicitly declared scratch is cleared even without a register request.
; CHECK-LABEL: stack_only:
; CHECK: mov r12, #0
; CHECK-NEXT: bx lr
define i32 @stack_only(i32 %x) "zeroize-stack"="used" { ret i32 %x }

; CHECK-LABEL: asked_for_both:
; CHECK: mov r12, #0
; CHECK-NEXT: bx lr
define i32 @asked_for_both(i32 %x) "zeroize-stack"="used" "zero-call-used-regs"="used-gpr" { ret i32 %x }

; CHECK-LABEL: untouched:
; CHECK-NOT: mov
; CHECK: bx lr
define i32 @untouched(i32 %x) { ret i32 %x }
