// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
.syntax unified
.arm
.text
.globl __wrap___cxa_end_cleanup
.type __wrap___cxa_end_cleanup,%function
__wrap___cxa_end_cleanup:
  .fnstart
  .save {r0,r1,r2,r3,r12,lr}
  push {r0,r1,r2,r3,r12,lr}
  // Unrelated callers do not have the protected carrier in R4.
  ldr r12,=__start_innercode
  cmp lr,r12
  blo .Lforward_cleanup
  ldr r12,=__stop_innercode
  cmp lr,r12
  bhs .Lforward_cleanup
  ldr r12,=private_observations
  ldr r2,=private_boundary_bytes
  mov r0,sp
  str r0,[r2,#192]
  .set index,0
  .rept 2
    ldr r0,[r12,#(index*112)]
    cmp r0,#0
    beq .Lbad_bounds
    add r1,r0,#96
    cmp r1,sp
    bhi .Lbad_bounds
    .set offset,0
    .rept 24
      ldr r3,[r0,#offset]
      str r3,[r2,#(index*96+offset)]
      .set offset,offset+4
    .endr
    .set index,index+1
  .endr
  add r2,r4,#16
  mov r0,#0
  ldr r12,=frame_size
  ldr r12,[r12]
  cmp r12,#32
  bne .Lbad_bounds
  mov r1,r2
.Lread_original:
  ldr r3,[r1],#4
  orr r0,r0,r3
  subs r12,r12,#4
  bne .Lread_original
  ldr r1,[r4,#4]
  bl boundary_probe
.Lbad_bounds:
  bl private_bounds_failure
.Lforward_cleanup:
  pop {r0,r1,r2,r3,r12,lr}
  b __real___cxa_end_cleanup
  .fnend
.size __wrap___cxa_end_cleanup,.-__wrap___cxa_end_cleanup
.bss
.p2align 2
.globl private_boundary_bytes
.type private_boundary_bytes,%object
private_boundary_bytes:
  .space 196
.size private_boundary_bytes,196
.section .note.GNU-stack,"",%progbits
