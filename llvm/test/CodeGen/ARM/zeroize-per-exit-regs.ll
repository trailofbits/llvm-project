; Which registers the clear covers is decided at each exit, and the two exits of
; this function need different registers: the tail call needs the ones it is
; passing arguments in, the return needs the one it is returning in. A set
; computed once for the function would have to spare the union and would clear
; less at both.
;
; Whether the step runs at all is still decided for the function, which is the
; other half of what this pins: one plan, many exits.

; RUN: llc -mtriple=armv7-unknown-linux-gnueabi -pei-print-clearing-sequence %s -o /dev/null 2>&1 | FileCheck %s --check-prefix=SEQ
; RUN: llc -mtriple=armv7-unknown-linux-gnueabi %s -o - | FileCheck %s

declare i32 @callee(i32, i32)

; SEQ-LABEL: clearing sequence for function 'two_exits':
; SEQ-NEXT:   %bb.1 tail-call: clear-stack=not-requested clear-registers=emitted clear-flags=unimplemented
; SEQ-NEXT:   %bb.2 return: clear-stack=not-requested clear-registers=emitted clear-flags=unimplemented
; SEQ-NEXT:  end clearing sequence for function 'two_exits'

; CHECK-LABEL: two_exits:
; The tail call is passing arguments in r0 and r1, so it keeps them and clears
; what is left.
; CHECK:         mov r0, r1
; CHECK-NEXT:    mov r1, r2
; CHECK-NEXT:    mov r3, #0
; CHECK-NEXT:    mov r12, #0
; CHECK-NEXT:    b callee
; The return is returning in r0, so it keeps only that one, and r2 -- which the
; tail-call exit had to spare -- is cleared here.
; CHECK:         add r0, r1, r2
; CHECK-NEXT:    mov r2, #0
; CHECK-NEXT:    mov r3, #0
; CHECK-NEXT:    mov r12, #0
; CHECK-NEXT:    bx lr
define i32 @two_exits(i1 %c, i32 %a, i32 %b) "zero-call-used-regs"="all-gpr" {
entry:
  br i1 %c, label %tail, label %plain

tail:
  %r = tail call i32 @callee(i32 %a, i32 %b)
  ret i32 %r

plain:
  %s = add i32 %a, %b
  ret i32 %s
}
