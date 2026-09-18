; RUN: not llc -mtriple=armv7-none-eabi %s -o /dev/null 2>&1 | FileCheck %s
; RUN: not llc -mtriple=thumbv6m-none-eabi %s -o /dev/null 2>&1 | FileCheck %s
; RUN: not llc -mtriple=thumbv7m-none-eabi %s -o /dev/null 2>&1 | FileCheck %s

; Unsupported layouts are errors, never successful partial frame clears.
; CHECK: error: {{.*}}in function dynamic {{.*}}ARM stack clearing does not support
define void @dynamic(i32 %n) "zeroize-stack"="used" {
  %p = alloca i8, i32 %n, align 4
  store volatile i8 1, ptr %p
  ret void
}

; CHECK: error: {{.*}}in function realigned {{.*}}ARM stack clearing does not support
define void @realigned() "zeroize-stack"="used" {
  %p = alloca i32, align 64
  store volatile i32 1, ptr %p
  ret void
}

; CHECK: error: {{.*}}in function cleanup {{.*}}ARM stack clearing does not support
declare void @_Unwind_Resume(ptr)
define void @cleanup(ptr %exn) "zeroize-stack"="used" {
  call void @_Unwind_Resume(ptr %exn)
  unreachable
}

; CHECK: error: {{.*}}in function variadic {{.*}}ARM stack clearing does not support
define void @variadic(i32 %x, ...) "zeroize-stack"="used" {
  ret void
}
