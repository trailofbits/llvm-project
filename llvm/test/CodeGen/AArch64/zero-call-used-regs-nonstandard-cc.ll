; RUN: llc -mtriple=aarch64-linux-gnu -verify-machineinstrs %s -o - \
; RUN:   | FileCheck %s --check-prefixes=CHECK,NORMAL
; RUN: llc -mtriple=aarch64-linux-gnu -mattr=+call-saved-x9 -verify-machineinstrs %s -o %t
; RUN: FileCheck %s --input-file=%t
; RUN: FileCheck %s --input-file=%t --check-prefix=PRESERVE

; The final per-function CSR list, rather than the usual AAPCS list, determines
; which registers are call-used. Return values must still survive the clearing.

define preserve_nonecc i64 @preserve_none() "zero-call-used-regs"="all-gpr" {
; CHECK-LABEL: preserve_none:
; PRESERVE-LABEL: preserve_none:
; PRESERVE-NOT: mov {{[wx]}}9, #0
; PRESERVE: ret
; CHECK-DAG: mov w0, #42
; NORMAL-DAG: mov x9, #0
; CHECK-DAG: mov x19, #0
; CHECK-DAG: mov x20, #0
; CHECK-DAG: mov x21, #0
; CHECK-DAG: mov x22, #0
; CHECK-DAG: mov x23, #0
; CHECK-DAG: mov x24, #0
; CHECK-DAG: mov x25, #0
; CHECK-DAG: mov x26, #0
; CHECK-DAG: mov x27, #0
; CHECK-DAG: mov x28, #0
; CHECK: ret
  ret i64 42
}

define ghccc void @ghc() "zero-call-used-regs"="all-gpr" {
; CHECK-LABEL: ghc:
; CHECK-DAG: mov x19, #0
; CHECK-DAG: mov x21, #0
; CHECK-DAG: mov x28, #0
; CHECK-DAG: mov x29, #0
; CHECK-NOT: mov x30, #0
; CHECK: ret
  ret void
}

define void @ordinary() "zero-call-used-regs"="all-gpr" {
; CHECK-LABEL: ordinary:
; CHECK-NOT: mov x19, #0
; CHECK-NOT: mov x20, #0
; CHECK-NOT: mov x21, #0
; CHECK-NOT: mov x28, #0
; CHECK: ret
  ret void
}

define i64 @ordinary_frame(i64 %value) "frame-pointer"="all" "zero-call-used-regs"="used-gpr" {
; CHECK-LABEL: ordinary_frame:
; CHECK: add x29, sp, #16
; CHECK: ldp x29, x30,
; CHECK-NOT: mov x29, #0
; CHECK: ret
  %slot = alloca i64, align 8
  store volatile i64 %value, ptr %slot
  %result = load volatile i64, ptr %slot
  ret i64 %result
}
