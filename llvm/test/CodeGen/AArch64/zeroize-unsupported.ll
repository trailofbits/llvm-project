; RUN: not llc -mtriple=aarch64-unknown-linux-gnu -mattr=+sve,+sme,+pauth %s -o /dev/null 2>&1 | \
; RUN: FileCheck %s
; RUN: llvm-extract -S --func=signed_with_pc %s -o %t.ll
; RUN: not llc -mtriple=aarch64-unknown-linux-gnu -mattr=+pauth %t.ll -o /dev/null 2>&1 | FileCheck %s --check-prefix=PC

; CHECK: error: {{.*}}in function dynamic {{.*}}AArch64 stack clearing does not support
define void @dynamic(i64 %n) "zeroize-stack"="used" {
  %p = alloca i8, i64 %n, align 16
  store volatile i8 0, ptr %p
  ret void
}

; CHECK: error: {{.*}}in function realigned {{.*}}AArch64 stack clearing does not support
define void @realigned() "zeroize-stack"="used" {
  %p = alloca i64, align 64
  store volatile i64 0, ptr %p
  ret void
}

; CHECK: error: {{.*}}in function safe_stack {{.*}}AArch64 stack clearing does not support
define void @safe_stack() safestack "zeroize-stack"="used" {
  ret void
}

; CHECK: error: {{.*}}in function signed_return {{.*}}AArch64 stack clearing does not support
; CHECK: error: {{.*}}in function signed_return {{.*}}"zeroize-flags" is not supported
define void @signed_return() "sign-return-address"="all" "zeroize-stack"="used" "zeroize-flags" {
  ret void
}

; An additional PC discriminator may require a scratch register after clearing.
; PC: error: {{.*}}in function signed_with_pc {{.*}}"zeroize-flags" is not supported
define void @signed_with_pc() "branch-protection-pauth-lr" "sign-return-address"="all" "zeroize-stack"="used" "zeroize-flags" {
  ret void
}

; CHECK: error: {{.*}}in function streaming {{.*}}AArch64 stack clearing does not support
; CHECK: error: {{.*}}in function streaming {{.*}}"zeroize-flags" is not supported
define void @streaming() "aarch64_pstate_sm_enabled" "zeroize-stack"="used" "zeroize-flags" {
  ret void
}
