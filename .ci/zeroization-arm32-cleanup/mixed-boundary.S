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
  // The linker wrapper also sees unprotected callers' cleanup transfers.
  ldr r12, =__start_innercode
  cmp lr, r12
  blo 2f
  ldr r12, =__stop_innercode
  cmp lr, r12
  bhs 2f
  add r2, r4, #16
  mov r0, #0
  ldr r12, =frame_size
  ldr r12, [r12]
  mov r1, r2
1:
  ldr r3, [r1], #4
  orr r0, r0, r3
  subs r12, r12, #4
  bne 1b
  ldr r1, [r4, #4]
  bl boundary_probe
2:
  pop {r0,r1,r2,r3,r12,lr}
  b __real___cxa_end_cleanup
  .fnend
.size __wrap___cxa_end_cleanup,.-__wrap___cxa_end_cleanup
.section .note.GNU-stack,"",%progbits
