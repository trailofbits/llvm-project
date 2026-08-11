; RUN: not llc -mtriple=x86_64-unknown-linux-gnu < %s -o /dev/null 2>&1 | FileCheck %s
; RUN: not llc -mtriple=i386-unknown-linux-gnu < %s -o /dev/null 2>&1 | FileCheck %s

; No target clears the stack frame yet, so every "zeroize-stack" request is
; reported rather than compiled into a function that leaves the frame intact.

; CHECK: error: {{.*}}in function used i32 (i32): "zeroize-stack" is not supported by this target
define i32 @used(i32 %x) "zeroize-stack"="used" {
  ret i32 %x
}

; CHECK: error: {{.*}}in function sensitive i32 (i32): "zeroize-stack" is not supported by this target
define i32 @sensitive(i32 %x) "zeroize-stack"="sensitive" {
  ret i32 %x
}

; The two capabilities are answered separately: x86 clears call-used registers,
; so that request is still discharged rather than swept up by the one it cannot
; satisfy.
; CHECK-NOT: in function regs
define i32 @regs(i32 %x) "zero-call-used-regs"="used-gpr" {
  ret i32 %x
}
