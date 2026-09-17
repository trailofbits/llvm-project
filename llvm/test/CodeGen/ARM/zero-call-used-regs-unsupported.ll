; RUN: not llc -mtriple=armv7-unknown-linux-gnueabi < %s -o /dev/null 2>&1 | FileCheck %s
; RUN: not llc -mtriple=thumbv6m-none-eabi < %s -o /dev/null 2>&1 | FileCheck %s
; RUN: not llc -mtriple=thumbv7m-none-eabi < %s -o /dev/null 2>&1 | FileCheck %s
; RUN: not llc -mtriple=thumbv8.1m.main-none-eabi -mattr=+mve < %s -o /dev/null 2>&1 | FileCheck %s

; ARM does not implement emitZeroCallUsedRegs, so supportsZeroCallUsedRegs is
; false and the request is reported. Before the query it was dropped silently.

; CHECK: error: {{.*}}in function used_gpr i32 (i32): "zero-call-used-regs" is not supported by this target
define i32 @used_gpr(i32 %x) "zero-call-used-regs"="used-gpr" {
  ret i32 %x
}

; Register classification must not enable clearing on a target that has no
; emitter, even when it can identify the requested GPR or argument registers.
; CHECK: error: {{.*}}in function all_gpr i32 (i32): "zero-call-used-regs" is not supported by this target
define i32 @all_gpr(i32 %x) "zero-call-used-regs"="all-gpr" {
  ret i32 %x
}

; CHECK: error: {{.*}}in function all_arg i32 (i32): "zero-call-used-regs" is not supported by this target
define i32 @all_arg(i32 %x) "zero-call-used-regs"="all-arg" {
  ret i32 %x
}

; CHECK: error: {{.*}}in function all i32 (i32): "zero-call-used-regs" is not supported by this target
define i32 @all(i32 %x) "zero-call-used-regs"="all" {
  ret i32 %x
}

; The naked case is reported against the function rather than the target, so it
; lives in zeroize-naked.ll. This file's message is about the target.

; "skip" asks for nothing, so there is nothing to report.
; CHECK-NOT: in function skip
define i32 @skip(i32 %x) "zero-call-used-regs"="skip" {
  ret i32 %x
}
