// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

// The fixture uses a private arena as its stack and starts with a known
// nonzero byte in every location. It snapshots exactly at the return boundary.
.arch armv8-a+sve
.text
.globl _start
.type _start,%function
_start:
  // One optional argument selects the second invocation.
  ldr x0, [sp]
  sub x0, x0, #1

  ldr x19, =snapshot
  ldr x20, =arena
  ldr x21, =entry
  mov w9, #0xa5
  mov x10, x20
  add x11, x21, #16
.Lseed:
  strb w9, [x10], #1
  cmp x10, x11
  b.ne .Lseed

  // The scalar PCS preserves only the low D halves of Z8-Z15. For vector PCS,
  // the protected function must preserve the full Z8-Z23 and P4-P15 values.
  .irp reg,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23
    mov z\reg\().b, #11
  .endr
  .irp reg,4,5,6,7,8,9,10,11,12,13,14,15
    ptrue p\reg\().b
  .endr
  ptrue p0.b
  mov z0.b, #5
  str x0, [x19, #192]
  mov sp, x21
#ifdef BASE
  bl base_victim
#else
  bl vector_victim
#endif
  stp x0, x1, [x19, #0]
  stp x2, x3, [x19, #16]
  stp x4, x5, [x19, #32]
  stp x6, x7, [x19, #48]
  stp x8, x9, [x19, #64]
  stp x10, x11, [x19, #80]
  stp x12, x13, [x19, #96]
  stp x14, x15, [x19, #112]
  stp x16, x17, [x19, #128]
  str x18, [x19, #144]
  mrs x9, nzcv
  mov x10, sp
  stp x9, x10, [x19, #152]
  str x21, [x19, #168]
  cntb x9
  str x9, [x19, #176]
  str xzr, [x19, #184]

  add x22, x19, #200
  .irp reg,0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31
    str z\reg, [x22]
    addvl x22, x22, #1
  .endr
  .irp reg,0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15
    str p\reg, [x22]
    addpl x22, x22, #1
  .endr
  // All predicate snapshots are safe to read before observing auxiliary FFR.
  rdffr p0.b
  str p0, [x22]
  addpl x22, x22, #1

  mov x1, x19
  sub x2, x22, x19
  mov x0, #1
  mov x8, #64
  svc #0
  cmp x0, x2
  cset x0, ne
  mov x8, #93
  svc #0
.size _start, .-_start

.globl fill_fixed
.type fill_fixed,%function
fill_fixed:
  // Dirty the fixed local and caller-saved state without adjusting the stack.
  mov x9, #0x6b6b
  movk x9, #0x6b6b, lsl #16
  movk x9, #0x6b6b, lsl #32
  movk x9, #0x6b6b, lsl #48
  .irp offset,0,16,32,48,64
    stp x9, x9, [x0, #\offset]
  .endr
  mov z0.b, #3
  mov z1.b, #7
  mov z24.b, #8
  pfalse p0.b
  ptrue p1.b
  setffr
#ifdef BASE
  ptrue p0.b
  ptrue p2.b, vl8
  bic p0.b, p0/z, p0.b, p2.b
  .irp reg,8,9,10,11,12,13,14,15
    mov z\reg\().b, p0/m, #13
  .endr
#endif
  mov x1, #103
  mov x12, #104
  mov x9, #0xf0000000
  msr nzcv, x9
  ret
.size fill_fixed, .-fill_fixed

.bss
.balign 16
snapshot:
  .skip 9008
arena:
  .skip 8192
entry:
  .skip 16

.section .note.GNU-stack,"",%progbits
