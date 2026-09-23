; "all" requests every vector register through every class that holds it, so
; XMM0 arrives alongside YMM0 and ZMM0. Each lane is cleared once, through its
; XMM register: a VEX or EVEX encoded xor zeroes the bits above the lane, and
; without AVX nothing can have written them.

; RUN: llc < %s -mtriple=x86_64-unknown-linux-gnu -mattr=+sse2 -verify-machineinstrs | FileCheck --check-prefix=SSE %s
; RUN: llc < %s -mtriple=x86_64-unknown-linux-gnu -mattr=+avx -verify-machineinstrs | FileCheck --check-prefix=AVX %s
; RUN: llc < %s -mtriple=x86_64-unknown-linux-gnu -mattr=+avx512f -verify-machineinstrs | FileCheck --check-prefixes=AVX512,AVX512F %s
; RUN: llc < %s -mtriple=x86_64-unknown-linux-gnu -mattr=+avx512f,+avx512bw -verify-machineinstrs | FileCheck --check-prefixes=AVX512,AVX512BW %s
; RUN: llc < %s -mtriple=x86_64-unknown-linux-gnu -mattr=+avx512f,+avx512bw -verify-machineinstrs -o /dev/null 2>&1 | count 0

define i32 @all(i32 %a) "zero-call-used-regs"="all" {
; SSE-LABEL: all:
; SSE-COUNT-16: xorps %xmm{{[0-9]+}}, %xmm{{[0-9]+}}
; SSE-NOT:      xorps
; SSE-NOT:      kxor
; SSE:          retq
;
; AVX-LABEL: all:
; AVX-COUNT-16: vxorps %xmm{{[0-9]+}}, %xmm{{[0-9]+}}, %xmm{{[0-9]+}}
; AVX-NOT:      xorps
; AVX-NOT:      kxor
; AVX:          retq
;
; AVX512-LABEL: all:
; AVX512-COUNT-16: vxorps %xmm{{[0-9]+}}, %xmm{{[0-9]+}}, %xmm{{[0-9]+}}
; AVX512-COUNT-16: vpxord %{{[xz]}}mm{{(1[6-9]|2[0-9]|3[01])}}, %{{[xz]}}mm{{[0-9]+}}, %{{[xz]}}mm{{[0-9]+}}
; AVX512-NOT:      xorps
; AVX512-NOT:      vpxord
; AVX512F-COUNT-8: kxorw %k0, %k0, %k{{[0-9]}}
; AVX512BW-COUNT-8: kxorq %k0, %k0, %k{{[0-9]}}
; AVX512-NOT:      kxor
; AVX512:          retq
  ret i32 %a
}
