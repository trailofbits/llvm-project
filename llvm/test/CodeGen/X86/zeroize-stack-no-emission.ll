; RUN: llc -mtriple=x86_64-linux-gnu -pei-print-clearing-sequence -verify-machineinstrs %s -o /dev/null 2>&1 | FileCheck %s
;
; An unsupported stack clear must not be reported as emitted or force a
; register clear. An explicit register request still runs independently.
; CHECK: warning: {{.*}}in function stack_only {{.*}}"zeroize-stack" is not supported by this target
; CHECK: clearing sequence for function 'stack_only':
; CHECK-NEXT: %bb.0 return: clear-stack=unsupported clear-registers=not-requested clear-flags=unimplemented
; CHECK-NEXT: end clearing sequence for function 'stack_only'
define void @stack_only() "zeroize-stack"="used" {
  ret void
}

; CHECK: warning: {{.*}}in function both {{.*}}"zeroize-stack" is not supported by this target
; CHECK: clearing sequence for function 'both':
; CHECK-NEXT: %bb.0 return: clear-stack=unsupported clear-registers=emitted clear-flags=unimplemented
; CHECK-NEXT: end clearing sequence for function 'both'
define i32 @both(i32 %x) "zeroize-stack"="used" "zero-call-used-regs"="used-gpr" {
  ret i32 %x
}
