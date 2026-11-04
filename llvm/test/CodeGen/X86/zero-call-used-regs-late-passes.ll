; The register clear marks what it cleared as read at the exit, in
; target-independent code, so that dead machine instruction elimination keeps
; the clears. That pass does not run after prologue/epilogue insertion by
; default, so it runs on its own here.

; RUN: llc -mtriple=x86_64-unknown-linux-gnu -stop-after=prolog-epilog %s -o - \
; RUN:   | llc -mtriple=x86_64-unknown-linux-gnu -x mir \
; RUN:     -run-pass=machine-cp,dead-mi-elimination \
; RUN:     -mcp-use-is-copy-instr -verify-machineinstrs -o - \
; RUN:   | FileCheck %s

; The return value stays in eax; the used argument registers are cleared, and
; the return reads each of them.
define i32 @used(i32 %a, i32 %b, i32 %c) "zero-call-used-regs"="used-gpr" {
; CHECK-LABEL: name: used
; CHECK:      = OR32rr
; CHECK-NEXT: $edi = XOR32rr undef $edi, undef $edi, implicit-def $eflags
; CHECK-NEXT: $edx = XOR32rr undef $edx, undef $edx, implicit-def $eflags
; CHECK-NEXT: $esi = XOR32rr undef $esi, undef $esi, implicit-def $eflags
; CHECK-NEXT: RET 0, $eax, implicit $edi, implicit $edx, implicit $esi
  %x = mul i32 %a, %b
  %y = or i32 %x, %c
  ret i32 %y
}


define void @all() "zero-call-used-regs"="all" {
; CHECK-LABEL: name: all
; CHECK: $eax = XOR32rr undef $eax, undef $eax, implicit-def $eflags
; CHECK-NEXT: $ecx = XOR32rr undef $ecx, undef $ecx, implicit-def $eflags
; CHECK-NEXT: $edi = XOR32rr undef $edi, undef $edi, implicit-def $eflags
; CHECK-NEXT: $edx = XOR32rr undef $edx, undef $edx, implicit-def $eflags
; CHECK-NEXT: $esi = XOR32rr undef $esi, undef $esi, implicit-def $eflags
; CHECK-NEXT: $r8d = XOR32rr undef $r8d, undef $r8d, implicit-def $eflags
; CHECK-NEXT: $r9d = XOR32rr undef $r9d, undef $r9d, implicit-def $eflags
; CHECK-NEXT: $r10d = XOR32rr undef $r10d, undef $r10d, implicit-def $eflags
; CHECK-NEXT: $r11d = XOR32rr undef $r11d, undef $r11d, implicit-def $eflags
; CHECK-NEXT: $xmm0 = V_SET0
; CHECK-NEXT: $xmm1 = V_SET0
; CHECK-NEXT: $xmm2 = V_SET0
; CHECK-NEXT: $xmm3 = V_SET0
; CHECK-NEXT: $xmm4 = V_SET0
; CHECK-NEXT: $xmm5 = V_SET0
; CHECK-NEXT: $xmm6 = V_SET0
; CHECK-NEXT: $xmm7 = V_SET0
; CHECK-NEXT: $xmm8 = V_SET0
; CHECK-NEXT: $xmm9 = V_SET0
; CHECK-NEXT: $xmm10 = V_SET0
; CHECK-NEXT: $xmm11 = V_SET0
; CHECK-NEXT: $xmm12 = V_SET0
; CHECK-NEXT: $xmm13 = V_SET0
; CHECK-NEXT: $xmm14 = V_SET0
; CHECK-NEXT: $xmm15 = V_SET0
; CHECK-NEXT: RET 0
  ret void
}
