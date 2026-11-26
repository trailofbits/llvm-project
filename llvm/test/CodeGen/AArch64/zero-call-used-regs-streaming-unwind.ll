; RUN: llc -mtriple=aarch64-linux-gnu -mattr=+sme2 -verify-machineinstrs %s -o - \
; RUN:   | FileCheck %s --check-prefixes=CHECK,SME
; RUN: llc -mtriple=aarch64-linux-gnu -mattr=+sme2,+sve -verify-machineinstrs %s -o - \
; RUN:   | FileCheck %s --check-prefixes=CHECK,SVE

; A streaming function returns in streaming mode, where SVE instructions are
; usable. Its landing pad is entered in non-streaming mode and resumes unwinding
; from there, so without SVE the same clears are not executable at that exit.
; Vector registers are cleared through their scalar views, and predicates only
; after a test of PSTATE.SM.

declare void @may_throw()
declare void @cleanup()
declare i32 @__gxx_personality_v0(...)

define i64 @used_counter(i64 %start, i64 %end) "zero-call-used-regs"="used" "aarch64_pstate_sm_enabled" personality ptr @__gxx_personality_v0 {
; CHECK-LABEL: used_counter:
; CHECK: cntp x0, pn8.b, vlx2
; CHECK: pfalse p8.b
; CHECK: ret
; CHECK: bl cleanup
; SME: mrs x[[MODE:[0-9]+]], SVCR
; SME-NEXT: tbz w[[MODE]], #0, [[TAIL:.LBB[0-9_]+]]
; SME-NEXT: // %bb.
; SME-NEXT: pfalse p8.b
; SME: [[TAIL]]:
; SME: mov x[[MODE]], #0
; SVE-NOT: SVCR
; SVE: pfalse p8.b
; SVE-NOT: SVCR
; CHECK: bl _Unwind_Resume
entry:
  invoke void @may_throw() to label %ok unwind label %lpad
ok:
  %counter = call target("aarch64.svcount") @llvm.aarch64.sve.whilelo.c8(
      i64 %start, i64 %end, i32 2)
  %count = call i64 @llvm.aarch64.sve.cntp.c8(target("aarch64.svcount") %counter, i32 2)
  ret i64 %count
lpad:
  %lp = landingpad { ptr, i32 } cleanup
  call void @cleanup()
  resume { ptr, i32 } %lp
}

define i64 @all_regs(i64 %value) "zero-call-used-regs"="all" "aarch64_pstate_sm_enabled" personality ptr @__gxx_personality_v0 {
; CHECK-LABEL: all_regs:
; CHECK: mov z0.d, #0
; CHECK: pfalse p15.b
; CHECK: ret
; CHECK: bl cleanup
; SME-NOT: {{z[0-9]+\.d}}
; SME: tbz w{{[0-9]+}}, #0, [[TAIL:.LBB[0-9_]+]]
; SME: pfalse p0.b
; SME: pfalse p15.b
; SME: [[TAIL]]:
; SME-NOT: {{z[0-9]+\.d|pfalse}}
; SME: fmov d0, xzr
; SME-NOT: {{z[0-9]+\.d|pfalse}}
; SVE: mov z0.d, #0
; SVE: pfalse p15.b
; CHECK: bl _Unwind_Resume
entry:
  invoke void @may_throw() to label %ok unwind label %lpad
ok:
  ret i64 %value
lpad:
  %lp = landingpad { ptr, i32 } cleanup
  call void @cleanup()
  resume { ptr, i32 } %lp
}
