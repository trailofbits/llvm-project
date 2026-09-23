; Register clearing is planned once and emitted at both return and tail-call
; exits. Each exit preserves its own outgoing registers.

; RUN: llc -mtriple=armv7-unknown-linux-gnueabi -pei-print-clearing-sequence %s -o /dev/null 2>&1 | FileCheck %s

declare i32 @callee(i32, i32)

; CHECK-NOT:  error:
; CHECK-LABEL: clearing sequence for function 'two_exits':
; CHECK-NEXT:  %bb.1 tail-call: clear-stack=not-requested clear-registers=emitted clear-flags=unimplemented
; CHECK-NEXT:  %bb.2 return: clear-stack=not-requested clear-registers=emitted clear-flags=unimplemented
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
