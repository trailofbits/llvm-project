; RUN: llc -mtriple=aarch64-linux-gnu -mattr=+sve2p1 -verify-machineinstrs %s -o - | FileCheck %s
; RUN: llc -mtriple=aarch64-linux-gnu -mattr=+sme2 -force-streaming \
; RUN:   -verify-machineinstrs %s -o - | FileCheck %s

; The predicate-as-counter register is dead after CNTP, while its scalar result
; must survive. It is used without referring to the corresponding P register.
define i64 @count_active(i64 %start, i64 %end) "zero-call-used-regs"="used" {
; CHECK-LABEL: count_active:
; CHECK: whilelo pn8.b, x0, x1, vlx2
; CHECK: cntp x0, pn8.b, vlx2
; CHECK-NEXT: pfalse p8.b
; CHECK-NEXT: ret
  %counter = call target("aarch64.svcount") @llvm.aarch64.sve.whilelo.c8(
      i64 %start, i64 %end, i32 2)
  %count = call i64 @llvm.aarch64.sve.cntp.c8(target("aarch64.svcount") %counter, i32 2)
  ret i64 %count
}
