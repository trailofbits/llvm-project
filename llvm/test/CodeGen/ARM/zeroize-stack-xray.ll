; RUN: split-file %s %t
; RUN: not llc -mtriple=armv7-unknown-linux-gnueabihf -stop-after=prolog-epilog \
; RUN:   %t/instrumented.ll -o /dev/null 2>&1 | FileCheck %s --check-prefix=DIAG
; RUN: llc -mtriple=armv7-unknown-linux-gnueabihf -verify-machineinstrs \
; RUN:   %t/never.ll -o - | FileCheck %s --check-prefix=NEVER --implicit-check-not=xray

; Function instrumentation is added after PEI and can recreate cleared state.
; DIAG: error: {{.*}}in function always {{.*}}ARM stack clearing does not support
; DIAG: error: {{.*}}in function threshold {{.*}}ARM stack clearing does not support

;--- instrumented.ll
define void @always() "zeroize-stack"="used" "function-instrument"="xray-always" {
  ret void
}

define void @threshold() "zeroize-stack"="sensitive" "xray-instruction-threshold"="1" {
  ret void
}

;--- never.ll
; NEVER-LABEL: never:
; NEVER: str r0, [sp]
; NEVER: mov r0, sp
; NEVER: mov r1, #0
; NEVER: str r1, [r0]
; NEVER: mov sp, r0
; NEVER: mov r0, #0
; NEVER: bx lr
define void @never(i32 %x) "zeroize-stack"="used" #0 {
  %p = alloca i32, align 4
  store volatile i32 %x, ptr %p
  ret void
}

attributes #0 = {
  "function-instrument"="xray-never" "xray-instruction-threshold"="1"
}
