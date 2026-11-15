; RUN: llc -mtriple=x86_64-unknown-linux-gnu < %s -o /dev/null 2>&1 | count 0
; RUN: not llc -mtriple=i386-unknown-linux-gnu < %s -o /dev/null 2>&1 | FileCheck %s
; RUN: not llc -mtriple=x86_64-unknown-linux-gnu -mattr=+lvi-cfi \
; RUN:   < %s -o /dev/null 2>&1 | FileCheck %s

; The LP64 implementation accepts both modes. Other frame/ABI protocols are
; diagnosed rather than compiling an annotation that clears nothing.

; CHECK: error: {{.*}}in function used i32 (i32): X86 stack clearing does not support
define i32 @used(i32 %x) "zeroize-stack"="used" {
  ret i32 %x
}

; CHECK: error: {{.*}}in function sensitive i32 (i32): X86 stack clearing does not support
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
