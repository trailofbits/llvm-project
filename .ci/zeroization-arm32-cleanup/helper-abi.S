// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
.syntax unified
.arm
.text
.globl invoke_checked
.type invoke_checked,%function
invoke_checked:
  push {r4-r11,lr}
  sub sp,sp,#4
  mov r12,r0
  mov r0,r1
  mov r1,r2
  mov r2,r3
  mov r4,#0x44
  mov r5,#0x55
  mov r6,#0x66
  mov r7,#0x77
  mov r8,#0x88
  mov r9,#0x99
  mov r10,#0xaa
  mov r11,#0xbb
  blx r12
  orr r1,r1,r2
  orr r1,r1,r3
  orr r1,r1,r12
  mrs r12,APSR
  and r12,r12,#0xf8000000
  orr r1,r1,r12
  cmp r1,#0
  bne .Lbad
  cmp r4,#0x44
  bne .Lbad
  cmp r5,#0x55
  bne .Lbad
  cmp r6,#0x66
  bne .Lbad
  cmp r7,#0x77
  bne .Lbad
  cmp r8,#0x88
  bne .Lbad
  cmp r9,#0x99
  bne .Lbad
  cmp r10,#0xaa
  bne .Lbad
  cmp r11,#0xbb
  bne .Lbad
  b .Ldone
.Lbad:
  mov r0,#99
.Ldone:
  add sp,sp,#4
  pop {r4-r11,pc}
.size invoke_checked,.-invoke_checked
.globl landing
nop
landing: nop
.section .note.GNU-stack,"",%progbits
