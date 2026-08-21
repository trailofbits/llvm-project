; RUN: llc -mtriple=x86_64-unknown-linux-gnu < %s -o /dev/null 2>&1 | FileCheck %s
; RUN: llc -mtriple=i386-unknown-linux-gnu < %s -o /dev/null 2>&1 | FileCheck %s

; No target clears the stack frame yet, so every "zeroize-stack" request is
; reported. llc runs without "not" to pin that it warns: an error would fire
; everywhere and leave the attribute impossible to compile at all.

; CHECK: warning: {{.*}}in function used i32 (i32): "zeroize-stack" is not supported by this target
define i32 @used(i32 %x) "zeroize-stack"="used" {
  ret i32 %x
}

; CHECK: warning: {{.*}}in function sensitive i32 (i32): "zeroize-stack" is not supported by this target
define i32 @sensitive(i32 %x) "zeroize-stack"="sensitive" {
  ret i32 %x
}

; The naked case is reported against the function rather than the target, so it
; lives in zeroize-naked.ll. This file's message is about the target.

; The two capabilities are answered separately: x86 still clears call-used
; registers rather than being swept up by the request it cannot satisfy.
; CHECK-NOT: in function regs
define i32 @regs(i32 %x) "zero-call-used-regs"="used-gpr" {
  ret i32 %x
}
