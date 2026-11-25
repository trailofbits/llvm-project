; RUN: llc -mtriple=aarch64-unknown-linux-gnu -mattr=+sve -verify-machineinstrs %s -o - | \
; RUN: FileCheck %s
; RUN: llc -mtriple=aarch64-unknown-linux-gnu -mattr=+sve -filetype=obj %s -o /dev/null
; RUN: llc -mtriple=aarch64-unknown-linux-gnu -mattr=+sve -stop-after=prolog-epilog \
; RUN: -verify-machineinstrs %s -o - | FileCheck %s --check-prefix=MEM

; Restored fixed slots stay owned until the clear. Both return registers remain
; intact while scratch registers are cleared, even with register mode skip.
; CHECK-LABEL: saved:
; CHECK-DAG: ldr d8, [x9]
; CHECK-DAG: ldr x19, [x9]
; CHECK: stp xzr, xzr, [x9]
; CHECK: mov sp, x9
; CHECK: mov x9, #0
; CHECK: ret
define { i64, double } @saved(i64 %x, double %y)
    "zeroize-stack"="used" "zero-call-used-regs"="skip" {
  call void asm sideeffect "", "~{x19},~{d8}"()
  %a = insertvalue { i64, double } poison, i64 %x, 0
  %b = insertvalue { i64, double } %a, double %y, 1
  ret { i64, double } %b
}

; CHECK-LABEL: saved_scalable:
; CHECK: str p4,
; CHECK: str z8,
; CHECK: ldr z8, [x9]
; CHECK: .cfi_restore b8
; CHECK: ldr p4, [x9]
; CHECK: addvl x10,
; CHECK: stp xzr, xzr, [x9]
; CHECK: mov sp, x9
; CHECK: mov x9, #0
; CHECK: mov x10, #0
; CHECK: ret
; MEM-LABEL: name: saved_scalable
; MEM: $z8 = frame-destroy LDR_ZXI {{.*}}(load (<vscale x 1 x s128>)
; MEM: $p4 = frame-destroy LDR_PXI {{.*}}(load (<vscale x 1 x s16>)
define aarch64_sve_vector_pcs void @saved_scalable() uwtable "zeroize-stack"="used" {
  call void asm sideeffect "", "~{z8},~{p4}"()
  ret void
}

; CHECK-LABEL: vector_return:
; CHECK-NOT: movi v0
; CHECK: stp xzr, xzr, [x9]
; CHECK: mov sp, x9
; CHECK-NOT: movi v0
; CHECK: ret
define <4 x i32> @vector_return(<4 x i32> %x)
    "zeroize-stack"="sensitive" "zero-call-used-regs"="all" {
  %p = alloca <4 x i32>, align 16
  store volatile <4 x i32> %x, ptr %p
  ret <4 x i32> %x
}
