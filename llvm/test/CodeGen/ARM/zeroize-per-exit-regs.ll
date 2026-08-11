; Which registers the clear covers is now decided at each exit, but whether the
; step runs at all is still decided for the function. The two are easy to
; confuse once one of them has moved, and a target that refuses the request is
; where the difference shows: ARM cannot clear call-used registers, so a
; function that asks for it has to be told once, however many exits it has, and
; every exit has to report the same refusal rather than some of them planning
; their own.

; RUN: not llc -mtriple=armv7-unknown-linux-gnueabi -pei-print-clearing-sequence %s -o /dev/null 2>&1 | FileCheck %s

declare i32 @callee(i32, i32)

; CHECK:      error: {{.*}}in function two_exits i32 (i1, i32, i32): "zero-call-used-regs" is not supported by this target
; CHECK-NOT:  error:
; CHECK-LABEL: clearing sequence for function 'two_exits':
; CHECK-NEXT:  %bb.1 tail-call: clear-stack=not-requested clear-registers=unsupported clear-flags=unimplemented
; CHECK-NEXT:  %bb.2 return: clear-stack=not-requested clear-registers=unsupported clear-flags=unimplemented
; CHECK-NEXT:  end clearing sequence for function 'two_exits'
define i32 @two_exits(i1 %c, i32 %a, i32 %b) "zero-call-used-regs"="used-gpr" {
entry:
  br i1 %c, label %tail, label %plain

tail:
  %r = tail call i32 @callee(i32 %a, i32 %b)
  ret i32 %r

plain:
  %s = add i32 %a, %b
  ret i32 %s
}
