; RUN: not llc -mtriple=thumbv7-windows-msvc -verify-machineinstrs %s -o /dev/null 2>&1 | FileCheck %s

; Register clearing is not implemented for Windows on Arm yet: the clears sit
; inside the epilogue the unwind info describes. Report the request rather than
; emit unwind info that does not match the code.

; CHECK: error: {{.*}}in function used_gpr i32 (i32): "zero-call-used-regs" is not supported by this target
define i32 @used_gpr(i32 %x) uwtable "zero-call-used-regs"="used-gpr" {
  ret i32 %x
}

; "skip" asks for nothing, so there is nothing to report.
; CHECK-NOT: in function skip
define i32 @skip(i32 %x) uwtable "zero-call-used-regs"="skip" {
  ret i32 %x
}
