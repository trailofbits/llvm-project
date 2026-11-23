  .text
  .globl abi_enter
  .type abi_enter, %function
abi_enter:
  .cfi_startproc
  stp x29, x30, [sp, #-48]!
  .cfi_def_cfa_offset 48
  .cfi_offset x29, -48
  .cfi_offset x30, -40
  stp x19, x20, [sp, #16]
  .cfi_offset x19, -32
  .cfi_offset x20, -24
  str d8, [sp, #32]
  .cfi_offset b8, -16
  str x21, [sp, #40]
  .cfi_offset x21, -8
  mov x21, #0x2121
  mov x19, #0x1919
  mov x20, #0x2020
  mov x9, #0x888
  fmov d8, x9
  bl outer
  mov x9, #0x1919
  cmp x19, x9
  b.ne 1f
  mov x9, #0x2020
  cmp x20, x9
  b.ne 1f
  fmov x9, d8
  cmp x9, #0x888
  b.ne 1f
  mov x9, #0x2121
  cmp x21, x9
  b.eq 2f
1: mov w0, #51
2: ldr x21, [sp, #40]
  ldr d8, [sp, #32]
  ldp x19, x20, [sp, #16]
  ldp x29, x30, [sp], #48
  ret
  .cfi_endproc
  .size abi_enter, .-abi_enter
  .globl markers_ok
  .type markers_ok, %function
markers_ok:
  mov x9,#0x1919
  cmp x19,x9
  b.ne 1f
  mov x9,#0x2020
  cmp x20,x9
  b.ne 1f
  fmov x9,d8
  cmp x9,#0x888
  b.ne 1f
  mov x9,#0x2121
  cmp x21,x9
  cset w0,eq
  ret
1: mov w0,#0
  ret
  .size markers_ok, .-markers_ok
  .section .note.GNU-stack,"",%progbits
