; RUN: llc -mtriple=aarch64-unknown-linux-gnu -mattr=+sve -verify-machineinstrs %s -o %t
; RUN: FileCheck %s < %t
; RUN: FileCheck %s --check-prefix=SVE-RETURN < %t
; RUN: llc -mtriple=aarch64-unknown-linux-gnu -mattr=+sve -filetype=obj %s -o /dev/null

declare void @use(ptr)
declare void @callee()

; CHECK-LABEL: small:
; CHECK: str x0, [sp
; CHECK: stp xzr, xzr, [x9]
; CHECK: mov sp, x9
; CHECK: mov x9, #0
; CHECK: ret
define i64 @small(i64 %x) "zeroize-stack"="used" {
  %p = alloca i64, align 8
  store volatile i64 %x, ptr %p
  ret i64 %x
}

; CHECK-LABEL: large:
; CHECK: ldr x30, [x9
; CHECK: stp xzr, xzr, [x9]
; CHECK: add x9, x9, #16
; CHECK: cmp x9, x10
; CHECK: b.ne
; CHECK: mov sp, x9
; CHECK: mov x9, #0
; CHECK: mov x10, #0
; CHECK: msr NZCV, xzr
; CHECK-NEXT: ret
define void @large() "zeroize-stack"="sensitive" "zeroize-flags" {
  %p = alloca [4096 x i8], align 16
  call void @use(ptr %p)
  ret void
}

; The scalable value must survive a call, requiring an actual SVE spill.
; CHECK-LABEL: scalable_spill:
; CHECK: str z0,
; CHECK: bl callee
; CHECK: ldr z0,
; CHECK: addvl x10,
; CHECK: stp xzr, xzr, [x9]
; CHECK: cmp x9, x10
; CHECK: mov sp, x9
; CHECK: mov x9, #0
; CHECK: mov x10, #0
; CHECK: ret
; SVE-RETURN-LABEL: scalable_spill:
; SVE-RETURN: ldr z0,
; SVE-RETURN-NOT: mov z0.
; SVE-RETURN: ret
define <vscale x 4 x i32> @scalable_spill(<vscale x 4 x i32> %x)
    "zeroize-stack"="used" "zero-call-used-regs"="all" {
  call void @callee()
  ret <vscale x 4 x i32> %x
}
