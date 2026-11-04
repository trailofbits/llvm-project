; Thumb-1 copies must survive non-default copy propagation as well as dead
; instruction elimination explicitly scheduled after PEI. ARM and Thumb-2
; also retain every emitted GPR and vector clear at the protected exit.
;
; RUN: llc -mtriple=armv7-none-eabi -mattr=+neon -stop-after=prolog-epilog %s -o - \
; RUN:   | llc -mtriple=armv7-none-eabi -mattr=+neon -x mir \
; RUN:     -run-pass=machine-cp,dead-mi-elimination \
; RUN:     -mcp-use-is-copy-instr -verify-machineinstrs -o - \
; RUN:   | FileCheck %s --check-prefixes=CHECK,WIDE,NEON
; RUN: llc -mtriple=thumbv7m-none-eabi -stop-after=prolog-epilog %s -o - \
; RUN:   | llc -mtriple=thumbv7m-none-eabi -x mir \
; RUN:     -run-pass=machine-cp,dead-mi-elimination \
; RUN:     -mcp-use-is-copy-instr -verify-machineinstrs -o - \
; RUN:   | FileCheck %s --check-prefixes=CHECK,WIDE
; RUN: llc -mtriple=thumbv6m-none-eabi -stop-after=prolog-epilog %s -o - \
; RUN:   | llc -mtriple=thumbv6m-none-eabi -x mir \
; RUN:     -run-pass=machine-cp,dead-mi-elimination \
; RUN:     -mcp-use-is-copy-instr -verify-machineinstrs -o - \
; RUN:   | FileCheck %s --check-prefixes=CHECK,THUMB1
; RUN: llc -mtriple=thumbv6m-none-eabi -mcp-use-is-copy-instr -verify-machineinstrs %s -o - \
; RUN:   | FileCheck %s --check-prefix=ASM

declare i32 @callee(i32, i32, i32)

define void @all() "zero-call-used-regs"="all" {
; CHECK-LABEL: name: all
; WIDE: $r0 = {{(t2)?}}MOVi 0,
; WIDE-NEXT: $r1 = {{(t2)?}}MOVi 0,
; WIDE-NEXT: $r2 = {{(t2)?}}MOVi 0,
; WIDE-NEXT: $r3 = {{(t2)?}}MOVi 0,
; WIDE-NEXT: $r12 = {{(t2)?}}MOVi 0,
; THUMB1: $r0, {{(dead )?}}$cpsr = tMOVi8 0,
; THUMB1-NEXT: $r1 = tMOVr {{(killed )?}}$r0,
; THUMB1-NEXT: $r2 = tMOVr {{(killed )?}}$r0,
; THUMB1-NEXT: $r3 = tMOVr {{(killed )?}}$r0,
; THUMB1-NEXT: $r12 = tMOVr {{(killed )?}}$r0,
; NEON-NEXT: $q0 = VMOVv4i32 0,
; NEON-NEXT: $q1 = VMOVv4i32 0,
; NEON-NEXT: $q2 = VMOVv4i32 0,
; NEON-NEXT: $q3 = VMOVv4i32 0,
; NEON-NEXT: $q8 = VMOVv4i32 0,
; NEON-NEXT: $q9 = VMOVv4i32 0,
; NEON-NEXT: $q10 = VMOVv4i32 0,
; NEON-NEXT: $q11 = VMOVv4i32 0,
; NEON-NEXT: $q12 = VMOVv4i32 0,
; NEON-NEXT: $q13 = VMOVv4i32 0,
; NEON-NEXT: $q14 = VMOVv4i32 0,
; NEON-NEXT: $q15 = VMOVv4i32 0,
; CHECK-NEXT: {{t?}}BX_RET
; ASM-LABEL: all:
; ASM: movs r0, #0
; ASM-NEXT: mov r1, r0
; ASM-NEXT: mov r2, r0
; ASM-NEXT: mov r3, r0
; ASM-NEXT: mov r12, r0
; ASM-NEXT: bx lr
  ret void
}

; R0 carries the result, while the used argument registers are cleared.
define i32 @return_value(i32 %a, i32 %b, i32 %c) "zero-call-used-regs"="used-gpr" {
; CHECK-LABEL: name: return_value
; WIDE: $r0 = {{(t2)?}}ORRrr
; WIDE-NEXT: $r1 = {{(t2)?}}MOVi 0,
; WIDE-NEXT: $r2 = {{(t2)?}}MOVi 0,
; THUMB1: $r0, dead $cpsr = tORR
; THUMB1-NEXT: $r1, {{(dead )?}}$cpsr = tMOVi8 0,
; THUMB1-NEXT: $r2 = tMOVr {{(killed )?}}$r1,
; CHECK-NEXT: {{t?}}BX_RET {{.*}}implicit {{(killed )?}}$r0
; ASM-LABEL: return_value:
; ASM: orrs r0, r2
; ASM-NEXT: movs r1, #0
; ASM-NEXT: mov r2, r1
; ASM-NEXT: bx lr
  %x = mul i32 %a, %b
  %y = or i32 %x, %c
  ret i32 %y
}

; A tail call keeps all three outgoing arguments. Thumb-1 uses a normal call
; and must instead preserve the result through the clears and frame restore.
define i32 @tail(i32 %a, i32 %b, i32 %c) "zero-call-used-regs"="all-gpr" {
; CHECK-LABEL: name: tail
; WIDE: $r3 = {{(t2)?}}MOVi 0,
; WIDE-NEXT: $r12 = {{(t2)?}}MOVi 0,
; WIDE-NEXT: TCRETURNdi @callee, 0, {{.*}}implicit {{(killed )?}}$r0
; WIDE-SAME: , implicit {{(killed )?}}$r1
; WIDE-SAME: , implicit {{(killed )?}}$r2
; THUMB1: tBL {{.*}}@callee, {{.*}}implicit $r0, implicit $r1, implicit $r2
; THUMB1-NEXT: $r1, {{(dead )?}}$cpsr = tMOVi8 0,
; THUMB1-NEXT: $r2 = tMOVr {{(killed )?}}$r1,
; THUMB1-NEXT: $r3 = tMOVr {{(killed )?}}$r1,
; THUMB1-NEXT: $r12 = tMOVr {{(killed )?}}$r1,
; THUMB1-NEXT: frame-destroy tPOP_RET {{.*}}implicit {{(killed )?}}$r0
; ASM-LABEL: tail:
; ASM: bl callee
; ASM-NEXT: movs r1, #0
; ASM-NEXT: mov r2, r1
; ASM-NEXT: mov r3, r1
; ASM-NEXT: mov r12, r1
; ASM-NEXT: pop
  %r = tail call i32 @callee(i32 %a, i32 %b, i32 %c)
  ret i32 %r
}
