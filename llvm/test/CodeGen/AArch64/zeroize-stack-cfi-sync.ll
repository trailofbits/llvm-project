; RUN: llc -O0 -mtriple=aarch64-unknown-linux-gnu -enable-tail-merge=false \
; RUN:   -verify-machineinstrs -filetype=obj %s -o %t
; RUN: llvm-objdump -dr --no-show-raw-insn %t | FileCheck %s --check-prefix=LAYOUT
; RUN: llvm-dwarfdump --eh-frame %t | FileCheck %s --check-prefix=CFI

declare void @use(ptr)

; The call in the second block is laid out after the first clearing epilogue.
; Its unwind row must still describe the live frame and all callee saves.
; LAYOUT-LABEL: <sync_exits>:
; LAYOUT: ret
; LAYOUT: bl
; LAYOUT-NEXT: R_AARCH64_CALL26 use
; LAYOUT: ret

; CFI-LABEL: FDE
; CFI: 0x0: CFA=WSP{{$}}
; CFI-NEXT: 0x{{[0-9a-f]+}}: CFA=WSP+96: W19=[CFA-8], W20=[CFA-16], W30=[CFA-32]{{$}}
; CFI-NOT: CFA=
define void @sync_exits(i1 %early) uwtable(sync) "zeroize-stack"="used" {
entry:
  %slot = alloca [64 x i8], align 16
  call void asm sideeffect "", "~{x19},~{x20}"()
  br i1 %early, label %first, label %second

first:
  ret void

second:
  call void @use(ptr %slot)
  ret void
}
