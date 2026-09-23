; RUN: llc -verify-machineinstrs -mtriple=armv7-unknown-linux-gnueabi < %s | FileCheck %s
; RUN: llc -verify-machineinstrs -mtriple=thumbv6m-none-eabi < %s | FileCheck %s
; RUN: llc -verify-machineinstrs -mtriple=thumbv7m-none-eabi < %s | FileCheck %s
; RUN: llc -verify-machineinstrs -mtriple=thumbv8.1m.main-none-eabi -mattr=+mve < %s | FileCheck %s

; ARM and Thumb opt into register clearing, including MVE subtargets.
; Exercise the capability query through PEI for GPR and non-GPR modes.

; CHECK-LABEL: used_gpr:
; CHECK: mov{{s?}} r2, #0
; CHECK: bx lr
define i32 @used_gpr(i32 %x) "zero-call-used-regs"="used-gpr" {
  call void asm sideeffect "", "~{r2}"()
  ret i32 %x
}

; CHECK-LABEL: all_gpr:
; CHECK: mov{{s?}} r1, #0
; CHECK: mov{{s?}} r2, {{(#0|r1)}}
; CHECK: bx lr
define i32 @all_gpr(i32 %x) "zero-call-used-regs"="all-gpr" {
  ret i32 %x
}

; CHECK-LABEL: all_arg:
; CHECK: mov{{s?}} r1, #0
; CHECK: mov{{s?}} r2, {{(#0|r1)}}
; CHECK: bx lr
define i32 @all_arg(i32 %x) "zero-call-used-regs"="all-arg" {
  ret i32 %x
}

; CHECK-LABEL: all:
; CHECK: mov{{s?}} r1, #0
; CHECK: mov{{s?}} r2, {{(#0|r1)}}
; CHECK: bx lr
define i32 @all(i32 %x) "zero-call-used-regs"="all" {
  ret i32 %x
}

; "skip" requests no clearing.
; CHECK-LABEL: skip:
; CHECK-NOT: mov
; CHECK: bx lr
define i32 @skip(i32 %x) "zero-call-used-regs"="skip" {
  ret i32 %x
}
