; A register clear is an instruction whose only effect is to overwrite a
; register nothing reads afterwards, which is what a pass that removes
; instructions with no live definitions looks for. What keeps it is the exit:
; the registers it wrote are recorded as used by the return, which says that
; their values at the point of leaving are part of what the function leaves
; behind.
;
; Nothing in the pipeline removes instructions on those grounds after prologue
; and epilogue insertion today, so this runs dead-mi-elimination over the result
; by hand. The difference between the two functions is the whole test: one keeps
; its clears because the return carries the record, the other loses every one of
; them because its exit has nowhere to carry it.
;
; trailofbits/vspells-ct-internal-notes#66.

; RUN: llc -mtriple=armv7-unknown-linux-gnueabi -stop-after=prolog-epilog %s -o - | FileCheck %s --check-prefix=MIR
; RUN: llc -mtriple=armv7-unknown-linux-gnueabi -stop-after=prolog-epilog %s -o - | \
; RUN:   llc -mtriple=armv7-unknown-linux-gnueabi -x mir -run-pass=dead-mi-elimination -o - | \
; RUN:   FileCheck %s --check-prefix=DCE

; The return names every register the clear wrote, and only those: r0 carries
; the return value and was never cleared, so it is named for its own reasons.
; MIR-LABEL: name: kept
; MIR:         $r2 = MOVi 0
; MIR-NEXT:    $r3 = MOVi 0
; MIR-NEXT:    $r12 = MOVi 0
; MIR-NEXT:    BX_RET 14 /* CC::al */, $noreg, implicit $r0, implicit $r2, implicit $r3, implicit $r12
; DCE-LABEL: name: kept
; DCE:         $r2 = MOVi 0
; DCE-NEXT:    $r3 = MOVi 0
; DCE-NEXT:    $r12 = MOVi 0
define i32 @kept(i32 %x) "zero-call-used-regs"="all-gpr" {
  ret i32 %x
}

; The control. An exit that leaves through an instruction the classification
; could not read is in scope and is cleared, but an opaque instruction's
; register operands describe whatever the asm string put there, so there is
; nowhere to record what the clear wrote. The clears are emitted and then they
; go, which is what the ones above would do if the record were doing nothing.
; MIR-LABEL: name: unanchored
; MIR:         $r0 = MOVi 0
; MIR:         $r12 = MOVi 0
; MIR-NEXT:    INLINEASM
; DCE-LABEL: name: unanchored
; DCE-NOT:     MOVi 0
; DCE:         INLINEASM
define void @unanchored() "zero-call-used-regs"="all-gpr" {
  call void asm sideeffect "svc #0", "~{memory}"()
  unreachable
}
