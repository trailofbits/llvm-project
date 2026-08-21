; A register clear writes a register nothing reads afterwards, which is what a
; dead instruction is. It is emitted precisely because nothing reads the
; register, so the machine-level reason to keep it is missing from the
; instruction itself. What supplies it is the exit: the cleared registers are
; recorded as implicit uses of the return, which says that their values at the
; point of leaving are part of what the function leaves behind.
;
; The second RUN line is what makes this more than a claim. It takes the code
; this pass emits and runs DeadMachineInstructionElim over it -- the pass that
; removes instructions for having no live definitions, and the one that would
; take the clears. Nothing in the default pipeline runs it after
; prologue/epilogue insertion, so this is defence in depth rather than a fix
; for something the compiler does today; running it by hand is how the property
; gets checked rather than assumed.
;
; -save-temp-labels on that line is what lets the MIR be read back at all. The
; EH labels around the invoke below are temporary symbols, and a temporary
; symbol is unnamed unless that flag is passed; the MIR printer writes an
; unnamed one as "<mcsymbol >", and the parser then asks MCContext for a symbol
; by the empty name and asserts. The flag only makes those symbols carry the
; .Ltmp names that hand-written MIR already spells out. It says nothing about
; what is selected or emitted, and the first and third RUN lines go without it.

; RUN: llc -mtriple=x86_64-unknown-linux-gnu -mattr=+avx -stop-after=prolog-epilog < %s | FileCheck %s --check-prefix=MIR
; RUN: llc -mtriple=x86_64-unknown-linux-gnu -mattr=+avx -save-temp-labels -stop-after=prolog-epilog < %s | llc -mtriple=x86_64-unknown-linux-gnu -mattr=+avx -x mir -run-pass=dead-mi-elimination -o - | FileCheck %s --check-prefix=DCE
; RUN: llc -mtriple=x86_64-unknown-linux-gnu -mattr=+avx < %s | FileCheck %s --check-prefix=ASM

declare void @sink()
declare i32 @__gxx_personality_v0(...)

; The register the function used is cleared, and the return says so.
; MIR-LABEL: name: anchored
; MIR:         $edi = XOR32rr undef $edi, undef $edi, implicit-def $eflags
; MIR-NEXT:    RET 0, $eax, implicit $edi

; And it is still there after the pass that would have removed it.
; DCE-LABEL: name: anchored
; DCE:         $edi = XOR32rr undef $edi, undef $edi, implicit-def $eflags
; DCE-NEXT:    RET 0, $eax, implicit $edi
define i32 @anchored(i32 %x) "zero-call-used-regs"="used-gpr" nounwind {
  ret i32 %x
}

; Each exit is anchored with what was cleared there, because each exit is
; cleared separately and need not clear the same registers.
; MIR-LABEL: name: every_return
; MIR:         $edi = XOR32rr undef $edi, undef $edi, implicit-def $eflags
; MIR-NEXT:    RET 0, killed $eax, implicit $edi
; MIR:         $edi = XOR32rr undef $edi, undef $edi, implicit-def $eflags
; MIR-NEXT:    RET 0, killed $eax, implicit $edi

; DCE-LABEL: name: every_return
; DCE:         $edi = XOR32rr undef $edi, undef $edi, implicit-def $eflags
; DCE-NEXT:    RET 0, killed $eax, implicit $edi
; DCE:         $edi = XOR32rr undef $edi, undef $edi, implicit-def $eflags
; DCE-NEXT:    RET 0, killed $eax, implicit $edi
define i32 @every_return(i32 %x) "zero-call-used-regs"="used-gpr" nounwind {
entry:
  %c = icmp sgt i32 %x, 0
  br i1 %c, label %pos, label %neg

pos:
  ret i32 1

neg:
  ret i32 2
}

; An exit that leaves by calling the routine that resumes unwinding is cleared,
; and is not anchored: it has no return to record anything on, and a call's
; register operands describe its arguments rather than what the function leaves
; behind. This is the control for the two tests above. The clear in the landing
; pad is emitted here and is gone after the pass runs, which is what the clears
; at the returns would do too if the anchoring were not doing anything.
; MIR-LABEL: name: unanchored_resume
; MIR:         bb.2.lpad (landing-pad):
; MIR:         $eax = XOR32rr undef $eax, undef $eax, implicit-def $eflags
; MIR:         CALL64pcrel32 target-flags(x86-plt) @_Unwind_Resume

; DCE-LABEL: name: unanchored_resume
; DCE:         bb.2.lpad (landing-pad):
; DCE-NOT:     XOR32rr
; DCE:         CALL64pcrel32 target-flags(x86-plt) @_Unwind_Resume
define void @unanchored_resume() "zero-call-used-regs"="used-gpr" personality ptr @__gxx_personality_v0 {
entry:
  invoke void @sink() to label %cont unwind label %lpad

cont:
  ret void

lpad:
  %l = landingpad { ptr, i32 } cleanup
  resume { ptr, i32 } %l
}

; What is named on the return is the register the clear writes, read back off
; the instruction that was emitted rather than taken from the set the clear was
; asked to cover, and the two differ for a vector register here. X86 clears a
; YMM register by writing its 128-bit part: a VEX-encoded xorps zeroes bits
; 128 and up for free, so one shorter instruction does the whole register. The
; register that exists to be named is therefore $xmm0, and it is enough --
; a definition is live as soon as any part of it is.
;
; Naming the narrower register is also the only thing that would do here.
; X86InsertVZeroUpper reads a YMM or ZMM register on a return as a return that
; carries a vector value and drops the vzeroupper in front of it, so a YMM on
; this return would hand the caller an AVX-to-SSE transition to pay -- which is
; what TargetFrameLowering::getClearedRegExitAnchor exists to let a target
; avoid, and what the ASM check below holds. X86's override of it has nothing
; to narrow on this path, because what buildClearRegister emits for a vector
; register is already the 128-bit write; it is the guard for a clear that ever
; does define the full-width register.
; MIR-LABEL: name: vector_anchor
; MIR:         $xmm0 = V_SET0
; MIR-NEXT:    RET 0, implicit $xmm0

; DCE-LABEL: name: vector_anchor
; DCE:         $xmm0 = V_SET0
; DCE-NEXT:    RET 0, implicit $xmm0

; The vzeroupper the function had before any of this is still emitted.
; ASM-LABEL: vector_anchor:
; ASM:         vxorps %xmm0, %xmm0, %xmm0
; ASM-NEXT:    vzeroupper
; ASM-NEXT:    retq
define void @vector_anchor(<8 x float> %v) "zero-call-used-regs"="used" nounwind {
  store volatile <8 x float> %v, ptr null
  ret void
}
