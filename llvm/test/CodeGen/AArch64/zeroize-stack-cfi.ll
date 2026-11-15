; RUN: llc -mtriple=aarch64-unknown-linux-gnu -verify-machineinstrs %s -o - | FileCheck %s
; RUN: llc -mtriple=aarch64-unknown-linux-gnu -filetype=obj %s -o /dev/null
; RUN: llc -O0 -mtriple=aarch64-unknown-linux-gnu -enable-tail-merge=false -verify-machineinstrs \
; RUN: %s -o - | FileCheck %s --check-prefix=MULTI
; RUN: llc -O0 -mtriple=aarch64-unknown-linux-gnu -filetype=obj %s -o /dev/null

declare void @callee(ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr)

; The outgoing area and frame record remain allocated until both 16-byte pairs
; are cleared. CFI switches from FP before FP is restored.
; CHECK-LABEL: outgoing:
; CHECK: bl callee
; CHECK: .cfi_def_cfa wsp, 32
; CHECK: ldr x29, [x9
; CHECK: .cfi_restore w29
; CHECK: stp xzr, xzr, [x9]
; CHECK: stp xzr, xzr, [x9, #16]
; CHECK: mov sp, x9
; CHECK: .cfi_def_cfa wsp, 0
; CHECK: mov x9, #0
; CHECK: ret
define void @outgoing(ptr %p) uwtable "frame-pointer"="all" "zeroize-stack"="used" {
  call void @callee(ptr %p, ptr %p, ptr %p, ptr %p, ptr %p, ptr %p, ptr %p, ptr %p, ptr %p, ptr %p)
  ret void
}

declare void @use(ptr)

; Each exit gets its own clearing loop. The second exit restores the original
; unwind state before reloading its saved registers and releasing the frame.
; MULTI-LABEL: two_exits:
; MULTI: .cfi_remember_state
; MULTI: .cfi_def_cfa wsp, 288
; MULTI: ldr x29, [x9]
; MULTI: .cfi_restore w29
; MULTI: stp xzr, xzr, [x9]
; MULTI: b.ne
; MULTI: mov sp, x9
; MULTI-NEXT: .cfi_def_cfa wsp, 0
; MULTI: msr NZCV, xzr
; MULTI-NEXT: ret
; MULTI: .cfi_restore_state
; MULTI: .cfi_def_cfa wsp, 288
; MULTI: ldr x29, [x9]
; MULTI: .cfi_restore w29
; MULTI: stp xzr, xzr, [x9]
; MULTI: b.ne
; MULTI: mov sp, x9
; MULTI-NEXT: .cfi_def_cfa wsp, 0
; MULTI: msr NZCV, xzr
; MULTI-NEXT: ret
define i64 @two_exits(i1 %choose, i64 %x)
    uwtable "frame-pointer"="all" "zeroize-stack"="used" "zeroize-flags" {
  %p = alloca [256 x i8], align 16
  store volatile i64 %x, ptr %p
  br i1 %choose, label %left, label %right

left:
  call void @use(ptr %p)
  ret i64 1

right:
  %v = load volatile i64, ptr %p
  ret i64 %v
}
