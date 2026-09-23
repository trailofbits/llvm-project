; The register clear marks what it cleared as read at the exit, in
; target-independent code, so that dead machine instruction elimination keeps
; the clears. That pass does not run after prologue/epilogue insertion by
; default, so it runs on its own here.

; RUN: llc -mtriple=x86_64-unknown-linux-gnu -stop-after=prolog-epilog %s -o - \
; RUN:   | llc -mtriple=x86_64-unknown-linux-gnu -x mir -run-pass=dead-mi-elimination -verify-machineinstrs -o - \
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
