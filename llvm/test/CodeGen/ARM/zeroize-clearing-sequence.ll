; ARM can clear registers even when stack clearing is unsupported. Keep both
; steps in the planned order and report the unsupported stack request.

; RUN: llc -mtriple=armv7-unknown-linux-gnueabi -pei-print-clearing-sequence %s -o /dev/null 2>&1 | FileCheck %s

; CHECK: warning: {{.*}}in function both i32 (i32): "zeroize-stack" is not supported by this target
; CHECK-LABEL: clearing sequence for function 'both':
; CHECK-NEXT:  %bb.0 return: clear-stack=unsupported clear-registers=emitted clear-flags=unimplemented
; CHECK-NEXT:  end clearing sequence for function 'both'
define i32 @both(i32 %x) "zeroize-stack"="used" "zero-call-used-regs"="used-gpr" {
  ret i32 %x
}

; ARM classifies its own tail-call returns as exits: nothing about which blocks
; are in scope is x86's. The tail call needs r0, so nothing is left to clear.
declare i32 @callee(i32)

; CHECK-LABEL: clearing sequence for function 'exits':
; CHECK-NEXT:  %bb.0 tail-call: clear-stack=not-requested clear-registers=emitted clear-flags=unimplemented
; CHECK-NEXT:  end clearing sequence for function 'exits'
define i32 @exits(i32 %x) "zero-call-used-regs"="used-gpr" {
  %r = tail call i32 @callee(i32 %x)
  ret i32 %r
}
