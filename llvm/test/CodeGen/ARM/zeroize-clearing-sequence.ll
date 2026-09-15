; ARM supports coordinated stack and register clearing.

; RUN: llc -mtriple=armv7-unknown-linux-gnueabi -pei-print-clearing-sequence %s -o /dev/null 2>&1 | FileCheck %s

declare i32 @callee(i32)

; CHECK-LABEL: clearing sequence for function 'both':
; CHECK-NEXT:  %bb.0 return: clear-stack=emitted clear-registers=emitted clear-flags=unimplemented
; CHECK-NEXT:  end clearing sequence for function 'both'
define i32 @both(i32 %x) "zeroize-stack"="used" "zero-call-used-regs"="used-gpr" {
  ret i32 %x
}

; ARM classifies its own tail-call returns as exits: nothing about which blocks
; are in scope is x86's. The tail call needs r0, so nothing is left to clear.
; CHECK-LABEL: clearing sequence for function 'exits':
; CHECK-NEXT:  %bb.0 tail-call: clear-stack=not-requested clear-registers=emitted clear-flags=unimplemented
; CHECK-NEXT:  end clearing sequence for function 'exits'
define i32 @exits(i32 %x) "zero-call-used-regs"="used-gpr" {
  %r = tail call i32 @callee(i32 %x)
  ret i32 %r
}
