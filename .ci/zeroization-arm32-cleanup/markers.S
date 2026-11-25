  .syntax unified
  .fpu neon
  .arm
  .text
  .global abi_enter
  .type abi_enter,%function
abi_enter:
  .fnstart
  .save {r4,r5,r6,lr}
  push {r4,r5,r6,lr}
  .vsave {d8}
  vpush {d8}
  movw r4,#0x1919
  movw r5,#0x2020
  movw r1,#0x888
  mov r2,#0
  vmov d8,r1,r2
  bl outer
  mov r6,r0
  bl markers_ok
  cmp r0,#1
  moveq r0,r6
  movne r0,#51
  vpop {d8}
  pop {r4,r5,r6,pc}
  .fnend
  .size abi_enter,.-abi_enter
  .global markers_ok
  .type markers_ok,%function
markers_ok:
  movw r1,#0x1919
  cmp r4,r1
  bne 1f
  movw r1,#0x2020
  cmp r5,r1
  bne 1f
  vmov r1,r2,d8
  cmp r2,#0
  bne 1f
  movw r2,#0x888
  cmp r1,r2
  moveq r0,#1
  movne r0,#0
  bx lr
1: mov r0,#0
  bx lr
  .size markers_ok,.-markers_ok
  .section .note.GNU-stack,"",%progbits
