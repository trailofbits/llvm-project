; RUN: not llc -mtriple=armv7-unknown-linux-gnueabi < %s -o /dev/null 2>&1 | FileCheck %s

; ARM does not implement emitZeroCallUsedRegs, so it answers
; supportsZeroCallUsedRegs with false and the request is reported. Before the
; query existed the empty default emission ran and the attribute was dropped
; without a word, leaving the registers holding what it asked to have cleared.

; CHECK: error: {{.*}}in function used_gpr i32 (i32): "zero-call-used-regs" is not supported by this target
define i32 @used_gpr(i32 %x) "zero-call-used-regs"="used-gpr" {
  ret i32 %x
}

; CHECK: error: {{.*}}in function all i32 (i32): "zero-call-used-regs" is not supported by this target
define i32 @all(i32 %x) "zero-call-used-regs"="all" {
  ret i32 %x
}

; "skip" asks for nothing, so there is nothing for the target to discharge and
; nothing to report.
; CHECK-NOT: in function skip
define i32 @skip(i32 %x) "zero-call-used-regs"="skip" {
  ret i32 %x
}
