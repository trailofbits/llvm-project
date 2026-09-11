; RUN: llc -mtriple=riscv32 -mattr=+d -verify-machineinstrs < %s | FileCheck %s
; RUN: llc -mtriple=riscv64 -mattr=+d -verify-machineinstrs < %s | FileCheck %s

declare void @sink(i64)

; CHECK-LABEL: ghc_used:
; CHECK-NOT:   li ra, 0
; CHECK:       ret
define ghccc void @ghc_used() "zero-call-used-regs"="used" {
  call void @sink(i64 7)
  ret void
}

; CHECK-LABEL: ghc_used_gpr:
; CHECK-NOT:   li ra, 0
; CHECK:       ret
define ghccc void @ghc_used_gpr() "zero-call-used-regs"="used-gpr" {
  call void @sink(i64 7)
  ret void
}

; CHECK-LABEL: ghc_all:
; CHECK-NOT:   li ra, 0
; CHECK:       ret
define ghccc void @ghc_all() "zero-call-used-regs"="all" {
  call void @sink(i64 7)
  ret void
}
