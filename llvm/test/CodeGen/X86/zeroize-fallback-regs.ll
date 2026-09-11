; The "used" modes clear only registers the function touched. Registers an
; instruction touches implicitly were not counted, so an asm clobber or a
; physical-register output kept its contents past the return.
; trailofbits/vspells-ct-internal-notes#24.

; RUN: llc -mtriple=x86_64-unknown-linux-gnu %s -o - | FileCheck %s

; The clobber list is the function's only mention of %rdi, and it is implicit.
; CHECK-LABEL: asm_clobber:
; CHECK:       #APP
; CHECK:       #NO_APP
; CHECK-NEXT:  xorl %edi, %edi
; CHECK-NEXT:  retq
define void @asm_clobber() "zero-call-used-regs"="used-gpr" {
  call void asm sideeffect "movq $$0x5ec4e7, %rdi",
                           "~{rdi},~{dirflag},~{fpsr},~{flags}"()
  ret void
}

; An output bound to a physical register is an implicit operand too.
; CHECK-LABEL: asm_output:
; CHECK:       #APP
; CHECK:       #NO_APP
; CHECK-NEXT:  xorl %edi, %edi
; CHECK-NEXT:  retq
define void @asm_output() "zero-call-used-regs"="used-gpr" {
  %v = call i64 asm sideeffect "movq $$0x5ec4e7, $0",
                               "={rdi},~{dirflag},~{fpsr},~{flags}"()
  ret void
}

; rdtsc defines %eax and %edx without naming them, and the result is discarded.
; CHECK-LABEL: rdtsc_discarded:
; CHECK:       # %bb.0:
; CHECK-NEXT:  rdtsc
; CHECK-NEXT:  xorl %eax, %eax
; CHECK-NEXT:  xorl %edx, %edx
; CHECK-NEXT:  retq
define void @rdtsc_discarded() "zero-call-used-regs"="used-gpr" {
  %t = call i64 @llvm.x86.rdtsc()
  ret void
}

; A function that touches no call-used register still clears none.
; CHECK-LABEL: touches_nothing:
; CHECK:       # %bb.0:
; CHECK-NEXT:  retq
define void @touches_nothing() "zero-call-used-regs"="used-gpr" {
  ret void
}

declare i64 @llvm.x86.rdtsc()
