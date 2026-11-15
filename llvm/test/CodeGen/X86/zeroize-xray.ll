; RUN: split-file %s %t
; RUN: not llc -mtriple=x86_64-unknown-linux-gnu -mattr=+sahf \
; RUN:   -stop-after=prolog-epilog %t/instrumented.ll -o /dev/null 2>&1 \
; RUN:   | FileCheck %s --check-prefix=DIAG
; RUN: llc -mtriple=x86_64-unknown-linux-gnu -mattr=+sahf \
; RUN:   -verify-machineinstrs %t/never.ll -o - \
; RUN:   | FileCheck %s --check-prefix=NEVER --implicit-check-not=xray

; XRay exit instrumentation runs after PEI and can write stack and flags.
; DIAG: error: {{.*}}in function instrumented_stack {{.*}}X86 stack clearing does not support
; DIAG: error: {{.*}}in function instrumented_flags {{.*}}"zeroize-flags" is not supported
; DIAG: error: {{.*}}in function threshold_stack {{.*}}X86 stack clearing does not support
; DIAG: error: {{.*}}in function threshold_flags {{.*}}"zeroize-flags" is not supported
; DIAG: error: {{.*}}in function custom_event {{.*}}X86 stack clearing does not support
; DIAG: error: {{.*}}in function typed_event {{.*}}X86 stack clearing does not support

;--- instrumented.ll
define void @instrumented_stack() "zeroize-stack"="used" "function-instrument"="xray-always" {
  ret void
}

define void @instrumented_flags() "zeroize-flags" "function-instrument"="xray-always" {
  ret void
}

define void @threshold_stack() "zeroize-stack"="used" "xray-instruction-threshold"="1" {
  ret void
}

define void @threshold_flags() "zeroize-flags" "xray-instruction-threshold"="1" {
  ret void
}

declare void @llvm.xray.customevent(ptr, i64)
declare void @llvm.xray.typedevent(i64, ptr, i64)

define void @custom_event(ptr %p, i64 %n) "zeroize-stack"="used" {
  call void @llvm.xray.customevent(ptr %p, i64 %n)
  ret void
}

define void @typed_event(ptr %p, i64 %n) "zeroize-stack"="used" {
  call void @llvm.xray.typedevent(i64 1, ptr %p, i64 %n)
  ret void
}

;--- never.ll
; NEVER-LABEL: never:
; NEVER: movq $0, -8(%rsp)
; NEVER: testl %eax, %eax
; NEVER-NEXT: sahf
; NEVER-NEXT: retq
define void @never(i64 %x) "zeroize-stack"="used" "zeroize-flags"
    "function-instrument"="xray-never" "xray-instruction-threshold"="1" {
  %p = alloca i64, align 8
  store volatile i64 %x, ptr %p
  ret void
}
