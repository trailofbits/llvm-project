; Register clears remain live through dead-machine-instruction elimination at
; ordinary returns and opaque exits. Each exit retains the physical registers
; written by its clearing sequence.
;
; RUN: llc -mtriple=armv7-unknown-linux-gnueabi -verify-machineinstrs \
; RUN:   -stop-after=prolog-epilog %s -o - | FileCheck %s --check-prefix=MIR
; RUN: llc -mtriple=armv7-unknown-linux-gnueabi -verify-machineinstrs \
; RUN:   -stop-after=prolog-epilog %s -o - | \
; RUN:   llc -mtriple=armv7-unknown-linux-gnueabi -verify-machineinstrs \
; RUN:     -x mir -run-pass=dead-mi-elimination -o - | \
; RUN:   FileCheck %s --check-prefix=DCE

; The return names every register the clear wrote, and only those: r0 carries
; the return value and was never cleared, so it is named for its own reasons.
; MIR-LABEL: name: kept
; MIR:         $r1 = MOVi 0
; MIR-NEXT:    $r2 = MOVi 0
; MIR-NEXT:    $r3 = MOVi 0
; MIR-NEXT:    $r12 = MOVi 0
; MIR-NEXT:    BX_RET 14 /* CC::al */, $noreg, implicit $r0, implicit $r1,
; MIR-SAME:    implicit $r2, implicit $r3, implicit $r12
; DCE-LABEL: name: kept
; DCE:         $r1 = MOVi 0
; DCE-NEXT:    $r2 = MOVi 0
; DCE-NEXT:    $r3 = MOVi 0
; DCE-NEXT:    $r12 = MOVi 0
define i32 @kept(i32 %x) "zero-call-used-regs"="all-gpr" {
  ret i32 %x
}

; Opaque exits retain their clears through the same mechanism as returns.
; MIR-LABEL: name: opaque
; MIR:         $r0 = MOVi 0
; MIR:         $r12 = MOVi 0
; MIR-NEXT:    INLINEASM
; DCE-LABEL: name: opaque
; DCE:         $r0 = MOVi 0
; DCE:         $r12 = MOVi 0
; DCE-NEXT:    INLINEASM
define void @opaque() "zero-call-used-regs"="all-gpr" {
  call void asm sideeffect "svc #0", "~{memory}"()
  unreachable
}
