// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#ifdef __APPLE__
#define SYMBOL(name) _##name
#else
#define SYMBOL(name) name
#endif

.text
.p2align 4
.globl SYMBOL(ces_probe)
#ifndef __APPLE__
.type SYMBOL(ces_probe), @function
#endif
SYMBOL(ces_probe):
  pushq %rbx
  pushq %r12
  pushq %r13
  pushq %r14
  pushq %r15
  movq %rdi, %rbx
  movq %rsi, %r12
  movl $1, %r13d
  movl $2, %r14d
  movl $3, %r15d
  movabsq $0x1122334455667788, %rax
  movq %rax, %rcx
  movq %rax, %rdx
  movq %rax, %rsi
  movq %rax, %rdi
  movq %rax, %r8
  movq %rax, %r9
  movq %rax, %r10
  movq %rax, %r11
  pcmpeqd %xmm0, %xmm0
.irp R,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15
  movdqa %xmm0, %xmm\R
.endr
  callq *%rbx
  // Capture state before any compiler-generated caller code executes.
  movq %rax, 0(%r12)
  movq %rcx, 8(%r12)
  movq %rdx, 16(%r12)
  movq %rsi, 24(%r12)
  movq %rdi, 32(%r12)
  movq %r8, 40(%r12)
  movq %r9, 48(%r12)
  movq %r10, 56(%r12)
  movq %r11, 64(%r12)
  movq %r13, 400(%r12)
  movq %r14, 408(%r12)
  movq %r15, 416(%r12)
  // This push uses the expired incoming-return-address slot, above the buffer.
  pushfq
  popq %r13
  movq %r13, 72(%r12)
.irp R,0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15
  movdqu %xmm\R, (80 + 16 * \R)(%r12)
.endr
  movq SYMBOL(ces_buffer_address)(%rip), %rsi
  leaq 336(%r12), %rdi
  movl $64, %ecx
  rep movsb
  popq %r15
  popq %r14
  popq %r13
  popq %r12
  popq %rbx
  retq
#ifndef __APPLE__
.size SYMBOL(ces_probe), .-SYMBOL(ces_probe)
#endif

// A positive control for the probe itself, independent of the compiler feature.
.p2align 4
.globl SYMBOL(ces_zero_fixture)
#ifndef __APPLE__
.type SYMBOL(ces_zero_fixture), @function
#endif
SYMBOL(ces_zero_fixture):
  leaq -64(%rsp), %rax
  movq %rax, SYMBOL(ces_buffer_address)(%rip)
.irp N,0,8,16,24,32,40,48,56
  movq $0, \N(%rax)
.endr
.irp R,0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15
  pxor %xmm\R, %xmm\R
.endr
  xorl %ecx, %ecx
  xorl %edx, %edx
  xorl %esi, %esi
  xorl %edi, %edi
  xorl %r8d, %r8d
  xorl %r9d, %r9d
  xorl %r10d, %r10d
  xorl %r11d, %r11d
  xorl %eax, %eax
  sahf
  retq
#ifndef __APPLE__
.size SYMBOL(ces_zero_fixture), .-SYMBOL(ces_zero_fixture)
.section .note.GNU-stack,"",@progbits
#endif
