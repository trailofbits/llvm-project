; The sequence is planned for every protected function, on every target, and a
; step the target cannot discharge is reported and then keeps its place in the
; order rather than collapsing it. ARM implements neither clearing the stack
; nor clearing the call-used registers, so both steps are refused here and the
; order is all that is left of them.

; RUN: not llc -mtriple=armv7-unknown-linux-gnueabi -pei-print-clearing-sequence %s -o /dev/null 2>&1 | FileCheck %s

declare i32 @callee(i32)

; CHECK: error: {{.*}}in function both i32 (i32): "zeroize-stack" is not supported by this target
; CHECK: error: {{.*}}in function both i32 (i32): "zero-call-used-regs" is not supported by this target
; CHECK-LABEL: clearing sequence for function 'both':
; CHECK-NEXT:  %bb.0 return: clear-stack=unsupported clear-registers=unsupported clear-flags=unimplemented
; CHECK-NEXT:  end clearing sequence for function 'both'
define i32 @both(i32 %x) "zeroize-stack"="used" "zero-call-used-regs"="used-gpr" {
  ret i32 %x
}

; The exits are classified the same way whatever the target can do with them:
; nothing about which blocks are in scope is x86's.
; CHECK-LABEL: clearing sequence for function 'exits':
; CHECK-NEXT:  %bb.0 tail-call: clear-stack=not-requested clear-registers=unsupported clear-flags=unimplemented
; CHECK-NEXT:  end clearing sequence for function 'exits'
define i32 @exits(i32 %x) "zero-call-used-regs"="used-gpr" {
  %r = tail call i32 @callee(i32 %x)
  ret i32 %r
}
