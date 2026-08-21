; RUN: llc -mtriple=x86_64-unknown-linux-gnu < %s -o /dev/null 2>&1 | FileCheck %s
; RUN: llc -mtriple=i386-unknown-linux-gnu < %s -o /dev/null 2>&1 | FileCheck %s

; No target clears the stack frame yet, so every "zeroize-stack" request is
; reported rather than compiled into a function that leaves the frame intact.
; The report is a warning, and llc is run without "not" to pin that: an error
; would fire on every target and leave the attribute impossible to compile
; anywhere, which removes it rather than reports it.

; CHECK: warning: {{.*}}in function used i32 (i32): "zeroize-stack" is not supported by this target
define i32 @used(i32 %x) "zeroize-stack"="used" {
  ret i32 %x
}

; CHECK: warning: {{.*}}in function sensitive i32 (i32): "zeroize-stack" is not supported by this target
define i32 @sensitive(i32 %x) "zeroize-stack"="sensitive" {
  ret i32 %x
}

; A naked function has no frame the compiler lays out, but it still carries the
; attribute, so it is told the request will not be met rather than left to
; assume it was.
; CHECK: warning: {{.*}}in function naked void (): "zeroize-stack" is not supported by this target
define void @naked() naked "zeroize-stack"="used" {
  ret void
}

; The two capabilities are answered separately: x86 clears call-used registers,
; so that request is still discharged rather than swept up by the one it cannot
; satisfy.
; CHECK-NOT: in function regs
define i32 @regs(i32 %x) "zero-call-used-regs"="used-gpr" {
  ret i32 %x
}
