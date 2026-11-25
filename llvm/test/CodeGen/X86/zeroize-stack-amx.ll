; RUN: llc -mtriple=x86_64-linux-gnu -mattr=+amx-tile,-sahf \
; RUN:   -verify-machineinstrs %s -o - | FileCheck %s

declare x86_amx @llvm.x86.tileloadd64.internal(i16, i16, ptr, i64)
declare void @llvm.x86.tilestored64.internal(i16, i16, ptr, i64, x86_amx)

; Managed AMX releases the tile state even when stack clearing replaces the
; ordinary epilogue.
; CHECK-LABEL: stack_only:
; CHECK: ldtilecfg
; CHECK: tilestored
; CHECK: movq $0, -8(%rsp)
; CHECK-NEXT: tilerelease
; CHECK-NEXT: retq
define void @stack_only(ptr %src, ptr %dst) "zeroize-stack"="used" {
  %tile = call x86_amx @llvm.x86.tileloadd64.internal(i16 4, i16 16, ptr %src, i64 16)
  call void @llvm.x86.tilestored64.internal(i16 4, i16 16, ptr %dst, i64 16, x86_amx %tile)
  ret void
}

; CHECK-LABEL: stack_and_flags:
; CHECK: ldtilecfg
; CHECK: tilestored
; CHECK: movq $0, -8(%rsp)
; CHECK-NEXT: tilerelease
; CHECK-NEXT: xorl %eax, %eax
; CHECK-NEXT: addq $1, %rax
; CHECK-NEXT: movq $0, %rax
; CHECK-NEXT: retq
define void @stack_and_flags(ptr %src, ptr %dst) "zeroize-stack"="used" "zeroize-flags" {
  %tile = call x86_amx @llvm.x86.tileloadd64.internal(i16 4, i16 16, ptr %src, i64 16)
  call void @llvm.x86.tilestored64.internal(i16 4, i16 16, ptr %dst, i64 16, x86_amx %tile)
  ret void
}
