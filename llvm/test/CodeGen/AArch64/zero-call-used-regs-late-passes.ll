; Explicitly run copy propagation and dead instruction elimination after PEI.
; Every emitted GPR and vector clear must survive; return values and outgoing
; arguments remain intact.
;
; RUN: llc -mtriple=aarch64-linux-gnu -stop-after=prolog-epilog %s -o - \
; RUN:   | llc -mtriple=aarch64-linux-gnu -x mir \
; RUN:     -run-pass=machine-cp,dead-mi-elimination \
; RUN:     -mcp-use-is-copy-instr -verify-machineinstrs -o - \
; RUN:   | FileCheck %s

declare i32 @callee(i32, i32, i32)

define void @all() "zero-call-used-regs"="all" {
; CHECK-LABEL: name: all
; CHECK: $x0 = MOVZXi 0, 0
; CHECK-NEXT: $x1 = MOVZXi 0, 0
; CHECK-NEXT: $x2 = MOVZXi 0, 0
; CHECK-NEXT: $x3 = MOVZXi 0, 0
; CHECK-NEXT: $x4 = MOVZXi 0, 0
; CHECK-NEXT: $x5 = MOVZXi 0, 0
; CHECK-NEXT: $x6 = MOVZXi 0, 0
; CHECK-NEXT: $x7 = MOVZXi 0, 0
; CHECK-NEXT: $x8 = MOVZXi 0, 0
; CHECK-NEXT: $x9 = MOVZXi 0, 0
; CHECK-NEXT: $x10 = MOVZXi 0, 0
; CHECK-NEXT: $x11 = MOVZXi 0, 0
; CHECK-NEXT: $x12 = MOVZXi 0, 0
; CHECK-NEXT: $x13 = MOVZXi 0, 0
; CHECK-NEXT: $x14 = MOVZXi 0, 0
; CHECK-NEXT: $x15 = MOVZXi 0, 0
; CHECK-NEXT: $x16 = MOVZXi 0, 0
; CHECK-NEXT: $x17 = MOVZXi 0, 0
; CHECK-NEXT: $x18 = MOVZXi 0, 0
; CHECK-NEXT: $q0 = MOVIv2d_ns 0
; CHECK-NEXT: $q1 = MOVIv2d_ns 0
; CHECK-NEXT: $q2 = MOVIv2d_ns 0
; CHECK-NEXT: $q3 = MOVIv2d_ns 0
; CHECK-NEXT: $q4 = MOVIv2d_ns 0
; CHECK-NEXT: $q5 = MOVIv2d_ns 0
; CHECK-NEXT: $q6 = MOVIv2d_ns 0
; CHECK-NEXT: $q7 = MOVIv2d_ns 0
; CHECK-NEXT: $q16 = MOVIv2d_ns 0
; CHECK-NEXT: $q17 = MOVIv2d_ns 0
; CHECK-NEXT: $q18 = MOVIv2d_ns 0
; CHECK-NEXT: $q19 = MOVIv2d_ns 0
; CHECK-NEXT: $q20 = MOVIv2d_ns 0
; CHECK-NEXT: $q21 = MOVIv2d_ns 0
; CHECK-NEXT: $q22 = MOVIv2d_ns 0
; CHECK-NEXT: $q23 = MOVIv2d_ns 0
; CHECK-NEXT: $q24 = MOVIv2d_ns 0
; CHECK-NEXT: $q25 = MOVIv2d_ns 0
; CHECK-NEXT: $q26 = MOVIv2d_ns 0
; CHECK-NEXT: $q27 = MOVIv2d_ns 0
; CHECK-NEXT: $q28 = MOVIv2d_ns 0
; CHECK-NEXT: $q29 = MOVIv2d_ns 0
; CHECK-NEXT: $q30 = MOVIv2d_ns 0
; CHECK-NEXT: $q31 = MOVIv2d_ns 0
; CHECK-NEXT: RET_ReallyLR
  ret void
}

define i32 @return_value(i32 %a, i32 %b, i32 %c) "zero-call-used-regs"="used-gpr" {
; CHECK-LABEL: name: return_value
; CHECK: $w0 = ORRWrr
; CHECK-NEXT: $x1 = MOVZXi 0, 0
; CHECK-NEXT: $x2 = MOVZXi 0, 0
; CHECK-NEXT: $x8 = MOVZXi 0, 0
; CHECK-NEXT: RET_ReallyLR implicit {{(killed )?}}$w0
  %x = mul i32 %a, %b
  %y = or i32 %x, %c
  ret i32 %y
}

define i32 @tail(i32 %a, i32 %b, i32 %c) "zero-call-used-regs"="all-gpr" {
; CHECK-LABEL: name: tail
; CHECK: $x3 = MOVZXi 0, 0
; CHECK-NEXT: $x4 = MOVZXi 0, 0
; CHECK-NEXT: $x5 = MOVZXi 0, 0
; CHECK-NEXT: $x6 = MOVZXi 0, 0
; CHECK-NEXT: $x7 = MOVZXi 0, 0
; CHECK-NEXT: $x8 = MOVZXi 0, 0
; CHECK-NEXT: $x9 = MOVZXi 0, 0
; CHECK-NEXT: $x10 = MOVZXi 0, 0
; CHECK-NEXT: $x11 = MOVZXi 0, 0
; CHECK-NEXT: $x12 = MOVZXi 0, 0
; CHECK-NEXT: $x13 = MOVZXi 0, 0
; CHECK-NEXT: $x14 = MOVZXi 0, 0
; CHECK-NEXT: $x15 = MOVZXi 0, 0
; CHECK-NEXT: $x16 = MOVZXi 0, 0
; CHECK-NEXT: $x17 = MOVZXi 0, 0
; CHECK-NEXT: $x18 = MOVZXi 0, 0
; CHECK-NEXT: TCRETURNdi @callee, 0, {{.*}}implicit {{(killed )?}}$w0
; CHECK-SAME: , implicit {{(killed )?}}$w1
; CHECK-SAME: , implicit {{(killed )?}}$w2
  %r = tail call i32 @callee(i32 %a, i32 %b, i32 %c)
  ret i32 %r
}
