; RUN: llc -mtriple=aarch64-linux-gnu -mattr=+sve -verify-machineinstrs < %s | FileCheck %s
; RUN: llc -mtriple=aarch64-linux-gnu -mattr=+sve -O0 -verify-machineinstrs < %s | FileCheck %s

; The nonallocatable FFR is caller-saved, including under the SVE vector PCS.
; These checks run the complete pipeline so a dead implicit FFR definition
; cannot be removed after PEI.

declare void @llvm.aarch64.sve.setffr()

define void @all() "zero-call-used-regs"="all" {
; CHECK-LABEL: all:
; CHECK: pfalse p0.b
; CHECK: wrffr p0.b
; CHECK: ret
  ret void
}

define void @used() "zero-call-used-regs"="used" {
; CHECK-LABEL: used:
; CHECK-DAG: setffr
; CHECK-DAG: pfalse p0.b
; CHECK: wrffr p0.b
; CHECK: ret
  call void @llvm.aarch64.sve.setffr()
  ret void
}

define void @unused() "zero-call-used-regs"="used" {
; CHECK-LABEL: unused:
; CHECK-NOT: wrffr
; CHECK: ret
  ret void
}

define void @gpr() "zero-call-used-regs"="all-gpr" {
; CHECK-LABEL: gpr:
; CHECK: setffr
; CHECK-NOT: wrffr
; CHECK: ret
  call void @llvm.aarch64.sve.setffr()
  ret void
}

define void @arg() "zero-call-used-regs"="all-arg" {
; CHECK-LABEL: arg:
; CHECK: setffr
; CHECK-NOT: wrffr
; CHECK: ret
  call void @llvm.aarch64.sve.setffr()
  ret void
}

define void @used_arg() "zero-call-used-regs"="used-arg" {
; CHECK-LABEL: used_arg:
; CHECK: setffr
; CHECK-NOT: wrffr
; CHECK: ret
  call void @llvm.aarch64.sve.setffr()
  ret void
}

define void @skip() "zero-call-used-regs"="skip" {
; CHECK-LABEL: skip:
; CHECK: setffr
; CHECK-NOT: wrffr
; CHECK: ret
  call void @llvm.aarch64.sve.setffr()
  ret void
}

define aarch64_sve_vector_pcs <vscale x 16 x i1> @predicate_result(
    <vscale x 16 x i1> %p) "zero-call-used-regs"="all" {
; CHECK-LABEL: predicate_result:
; CHECK-NOT: pfalse p0.b
; CHECK-NOT: pfalse p4.b
; CHECK: pfalse p1.b
; CHECK: pfalse p2.b
; CHECK: pfalse p3.b
; CHECK: wrffr p1.b
; CHECK: ret
  ret <vscale x 16 x i1> %p
}
