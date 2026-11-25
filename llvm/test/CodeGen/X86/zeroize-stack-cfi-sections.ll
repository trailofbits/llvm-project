; RUN: llc -mtriple=x86_64-linux-gnu -basic-block-sections=all \
; RUN:   -verify-machineinstrs -verify-cfiinstrs %s -o - | FileCheck %s --check-prefix=ASM
; RUN: llc -mtriple=x86_64-linux-gnu -basic-block-sections=all \
; RUN:   -verify-machineinstrs -verify-cfiinstrs -filetype=obj %s -o %t
; RUN: llvm-dwarfdump --eh-frame %t | FileCheck %s --check-prefix=CFI

; Keep the save slots live through the loop. In the final section, unwind
; rules must stop referencing each slot before it is cleared.
; ASM-LABEL: static_frame:
; ASM: movq $128, %r10
; ASM-LABEL: static_frame.__part.1:
; ASM: movq $0, (%r11)
; ASM-LABEL: static_frame.__part.2:
; ASM: movq 128(%rsp), %rbx
; ASM: movq 136(%rsp), %r12
; ASM: movq 144(%rsp), %rbp
; ASM: movq $0, 128(%rsp)
; ASM-NEXT: movq $0, 136(%rsp)
; ASM-NEXT: movq $0, 144(%rsp)

; CFI-LABEL: FDE
; CFI: CFA=RBP+16: RBX=[CFA-32], RBP=[CFA-16], R12=[CFA-24], RIP=[CFA-8]
; CFI-LABEL: FDE
; CFI: CFA=RBP+16: RBX=[CFA-32], RBP=[CFA-16], R12=[CFA-24], RIP=[CFA-8]
; CFI-LABEL: FDE
; CFI: CFA=RSP+160: RBX=[CFA-32], RBP=[CFA-16], R12=[CFA-24], RIP=[CFA-8]
; CFI: CFA=RSP+160: RBP=[CFA-16], R12=[CFA-24], RIP=[CFA-8]
; CFI: CFA=RSP+160: RBP=[CFA-16], RIP=[CFA-8]
; CFI: CFA=RSP+160: RIP=[CFA-8]{{$}}
; CFI: CFA=RSP+8: RIP=[CFA-8]{{$}}
define void @static_frame(i64 %x) uwtable(async) noredzone
    "frame-pointer"="all" "zeroize-stack"="used" {
  %p = alloca [128 x i8], align 8
  store volatile i64 %x, ptr %p
  call void asm sideeffect "", "~{rbx},~{r12}"()
  ret void
}
