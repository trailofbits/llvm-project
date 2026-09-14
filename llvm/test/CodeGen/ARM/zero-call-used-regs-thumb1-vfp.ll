; RUN: split-file %s %t
; RUN: not llc -mtriple=thumbv6-none-eabi -mattr=+vfp2 %t/fp.ll -o /dev/null 2>&1 | FileCheck %s --check-prefix=REFUSED
; RUN: llc -mtriple=thumbv6-none-eabi -mattr=+vfp2 -verify-machineinstrs %t/gpr.ll -o - | FileCheck %s --check-prefix=GPR

; The hardware may have a VFP register file, but Thumb-1 cannot emit VFP
; instructions. Reject modes that could require clearing it, while retaining
; the core-register modes on the same configuration.
; REFUSED: error: {{.*}}in function all_regs void (): "zero-call-used-regs" is not supported by this target
; GPR-LABEL: core_regs:
; GPR: movs r0, #0
; GPR: mov r12, r0
; GPR-NEXT: bx lr

;--- fp.ll
define void @all_regs() "zero-call-used-regs"="all" { ret void }

;--- gpr.ll
define void @core_regs() "zero-call-used-regs"="all-gpr" { ret void }
