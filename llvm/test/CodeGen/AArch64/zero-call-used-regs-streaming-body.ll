; RUN: llc -mtriple=aarch64-linux-gnu -mattr=+sme2 -verify-machineinstrs %s -o - \
; RUN:   | FileCheck %s --check-prefixes=CHECK,SME
; RUN: llc -mtriple=aarch64-linux-gnu -mattr=+sme2,+sve -verify-machineinstrs %s -o - \
; RUN:   | FileCheck %s --check-prefixes=CHECK,SVE

; A locally streaming function returns in non-streaming mode. SVE instructions
; are only legal at that exit when the target has SVE itself. Without SVE,
; SMSTOP has already zeroed the predicate registers and the upper Z-register
; bits, so only the low 128 bits of the vector registers remain to clear.

declare void @streaming_callee() "aarch64_pstate_sm_enabled"

define i64 @used_counter(i64 %start, i64 %end) "zero-call-used-regs"="used" "aarch64_pstate_sm_body" {
; CHECK-LABEL: used_counter:
; CHECK: cntp x0, pn8.b, vlx2
; CHECK: smstop sm
; SME-NOT: pfalse
; SVE: pfalse p8.b
; CHECK: ret
  %counter = call target("aarch64.svcount") @llvm.aarch64.sve.whilelo.c8(
      i64 %start, i64 %end, i32 2)
  %count = call i64 @llvm.aarch64.sve.cntp.c8(target("aarch64.svcount") %counter, i32 2)
  ret i64 %count
}

define i64 @all_regs(i64 %value) "zero-call-used-regs"="all" "aarch64_pstate_sm_body" {
; CHECK-LABEL: all_regs:
; CHECK: smstop sm
; SME-NOT: {{z[0-9]+\.d|pfalse}}
; SME: fmov d0, xzr
; SME-NOT: {{z[0-9]+\.d|pfalse}}
; SME: fmov d31, xzr
; SME-NOT: {{z[0-9]+\.d|pfalse}}
; SVE: mov z0.d, #0
; SVE: mov z31.d, #0
; SVE: pfalse p0.b
; SVE: pfalse p15.b
; CHECK: ret
  call void @streaming_callee()
  ret i64 %value
}
