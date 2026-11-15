; RUN: not llc -mtriple=x86_64-unknown-linux-gnu %s -o /dev/null 2>&1 | FileCheck %s

; CHECK: error: {{.*}}in function dynamic {{.*}}X86 stack clearing does not support
define void @dynamic(i64 %n) "zeroize-stack"="used" {
  %p = alloca i8, i64 %n, align 8
  store volatile i8 1, ptr %p
  ret void
}

; CHECK: error: {{.*}}in function realigned {{.*}}X86 stack clearing does not support
define void @realigned() "zeroize-stack"="used" {
  %p = alloca i64, align 64
  store volatile i64 1, ptr %p
  ret void
}

; CHECK: error: {{.*}}in function variadic {{.*}}X86 stack clearing does not support
define void @variadic(i64 %x, ...) "zeroize-stack"="used" {
  ret void
}

; CHECK: error: {{.*}}in function safestack {{.*}}X86 stack clearing does not support
define void @safestack() safestack "zeroize-stack"="used" {
  ret void
}

declare i64 @llvm.x86.flags.read.u64()

; The PUSH/POP used by the intrinsic leaves a transient slot below the fixed
; frame. Reject it until ownership includes that slot.
; CHECK: error: {{.*}}in function transient_push {{.*}}X86 stack clearing does not support
define i64 @transient_push() "zeroize-stack"="used" {
  %flags = call i64 @llvm.x86.flags.read.u64()
  ret i64 %flags
}
