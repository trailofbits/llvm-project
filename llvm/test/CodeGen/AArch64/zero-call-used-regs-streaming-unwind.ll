; RUN: llc -mtriple=aarch64-linux-gnu -mattr=+sme2 -verify-machineinstrs %s -o - \
; RUN:   | FileCheck %s --check-prefixes=CHECK,SME
; RUN: llc -mtriple=aarch64-linux-gnu -mattr=+sme2,+sve -verify-machineinstrs %s -o - \
; RUN:   | FileCheck %s --check-prefixes=CHECK,SVE

; A streaming function returns in streaming mode, where SVE instructions are
; usable. _Unwind_Resume has a non-streaming interface. Without SVE, clear
; vector registers through their scalar views and omit the predicate clears
; at the call.

declare void @may_throw()
declare void @cleanup()
declare i32 @__gxx_personality_v0(...)

define i64 @used_counter(i64 %start, i64 %end) "zero-call-used-regs"="used" "aarch64_pstate_sm_enabled" personality ptr @__gxx_personality_v0 {
; CHECK-LABEL: used_counter:
; CHECK: cntp x0, pn8.b, vlx2
; CHECK: pfalse p8.b
; CHECK: ret
; CHECK: bl cleanup
; SME-NOT: {{SVCR|pfalse}}
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
; SME-NOT: {{SVCR|z[0-9]+\.d|pfalse}}
; SME: fmov d0, xzr
; SME-NOT: {{SVCR|z[0-9]+\.d|pfalse}}
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

; At _Unwind_Resume, X0 holds the exception object and P0 is the only
; argument register selected for clearing. The call needs no mode test or
; scratch register; the ordinary streaming return must still clear P0.
define i64 @used_arg(i64 %arg, <vscale x 16 x i1> %pred) "zero-call-used-regs"="used-arg" "aarch64_pstate_sm_enabled" personality ptr @__gxx_personality_v0 {
; CHECK-LABEL: used_arg:
; CHECK: pfalse p0.b
; CHECK: ret
; CHECK: bl cleanup
; SME-NOT: {{SVCR|pfalse}}
; SVE-NOT: SVCR
; SVE: pfalse p0.b
; CHECK: bl _Unwind_Resume
entry:
  %count = call i64 @llvm.aarch64.sve.cntp.nxv16i1(<vscale x 16 x i1> %pred, <vscale x 16 x i1> %pred)
  invoke void @may_throw() to label %ok unwind label %lpad
ok:
  %result = add i64 %arg, %count
  ret i64 %result
lpad:
  %lp = landingpad { ptr, i32 } cleanup
  call void @cleanup()
  resume { ptr, i32 } %lp
}
