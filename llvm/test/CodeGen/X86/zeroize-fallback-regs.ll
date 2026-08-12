; The set of registers a "used" mode clears is a narrowing: it drops the
; registers the function never touched. A narrowing has to be able to justify
; every register it drops, and this one could not. Registers an instruction
; touches implicitly were not counted as touched, so they were dropped from the
; set and kept their contents past the return.
;
; Inline assembly is the case that made it visible, because every register an
; asm block names reaches the machine layer as an implicit operand: a function
; whose only register traffic was an asm block cleared nothing at all.
;
; trailofbits/vspells-ct-internal-notes#24.

; RUN: llc -mtriple=x86_64-unknown-linux-gnu %s -o - | FileCheck %s

; The asm writes a secret into a call-used argument register and declares it in
; the clobber list, which is the whole of what the compiler can know about it.
; That declaration is the function's only mention of %rdi, and it is implicit.
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

; An output bound to a physical register is written down the same way, so it
; was missed the same way even though the asm block has a result in the IR.
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

; Not only inline assembly: an instruction that defines a register on the side
; is opaque here in the same way. rdtsc leaves the counter in %eax and %edx and
; names neither, and the result is discarded, so nothing else in the function
; mentions them either.
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

; The mode is still a narrowing, and this is what keeps the change honest: a
; function that touches no call-used register still clears none. Counting
; implicit operands widened "used" towards "all"; it did not collapse it into
; it.
; CHECK-LABEL: touches_nothing:
; CHECK:       # %bb.0:
; CHECK-NEXT:  retq
define void @touches_nothing() "zero-call-used-regs"="used-gpr" {
  ret void
}

declare i64 @llvm.x86.rdtsc()
