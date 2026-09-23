; RUN: split-file %s %t
; RUN: not llc -mtriple=thumbv6m-none-eabi -verify-machineinstrs %t/thumb1.ll -o /dev/null 2>&1 | FileCheck %s --check-prefix=THUMB1-ERR
; RUN: llc -mtriple=thumbv8m.base-none-eabi -verify-machineinstrs %t/thumb1.ll -o - | FileCheck %s --check-prefix=BASELINE
; RUN: not llc -mtriple=armv7-unknown-linux-gnueabihf -mattr=-neon -verify-machineinstrs %t/indirect.ll -o /dev/null 2>&1 | FileCheck %s --check-prefix=TAIL-ERR
; RUN: not llc -mtriple=thumbv7-unknown-linux-gnueabihf -mattr=-neon -verify-machineinstrs %t/indirect.ll -o /dev/null 2>&1 | FileCheck %s --check-prefix=TAIL-ERR
; RUN: llc -mtriple=armv7-unknown-linux-gnueabihf -mattr=-neon -verify-machineinstrs %t/direct.ll -o - | FileCheck %s --check-prefix=DIRECT
; RUN: llc -mtriple=thumbv7-unknown-linux-gnueabihf -mattr=-neon -verify-machineinstrs %t/direct.ll -o - | FileCheck %s --check-prefix=DIRECT

; A vector return occupies r0-r3, and r4-r7 hold the caller's values. Clearing
; r12 on Thumb-1 needs a zeroed low register, so even a plain return can exhaust
; the available scratch registers. Diagnose the unsupported clear rather than
; silently omit it or clobber part of the return value.
;
; Armv8-M Baseline can materialize zero directly in r12 and needs no scratch.

;--- thumb1.ll
define <4 x i32> @all_gpr(<4 x i32> %x) "zero-call-used-regs"="all-gpr" {
; THUMB1-ERR: error: {{.*}}in function all_gpr {{.*}}: clearing the call-used registers needs a register to hold zero and none is free at this exit
; BASELINE-LABEL: all_gpr:
; BASELINE-NOT:   {{r[0-3]([^0-9]|$)}}
; BASELINE:       movw r12, #0
; BASELINE-NEXT:  bx lr
  ret <4 x i32> %x
}

; The same limitation applies to used-gpr when the function touches r12.
define <4 x i32> @used_gpr(<4 x i32> %x) "zero-call-used-regs"="used-gpr" {
; THUMB1-ERR: error: {{.*}}in function used_gpr {{.*}}: clearing the call-used registers needs a register to hold zero and none is free at this exit
; BASELINE-LABEL: used_gpr:
; BASELINE-NOT:   {{r[0-3]([^0-9]|$)}}
; BASELINE:       movw r12, #0
; BASELINE-NEXT:  bx lr
  call void asm sideeffect "", "~{r12}"()
  ret <4 x i32> %x
}

;--- indirect.ll
; The conversion uses s0. At the tail call r0-r3 hold the integer arguments,
; r12 holds the destination, and the other GPRs must retain the caller's values.
; There is no free GPR from which to clear s0, even outside Windows epilogues.
define i32 @indirect_tail(ptr %callee, float %a, i32 %b, i32 %c, i32 %d) "zero-call-used-regs"="used" {
; TAIL-ERR: error: {{.*}}in function indirect_tail {{.*}}: clearing the call-used registers needs a register to hold zero and none is free at this exit
  %x = fptosi float %a to i32
  %r = tail call i32 %callee(i32 %x, i32 %b, i32 %c, i32 %d)
  ret i32 %r
}

;--- direct.ll
; A direct tail call leaves r12 free for the zero without changing r0-r3.
declare i32 @callee(i32, i32, i32, i32)

define i32 @direct_tail(float %a, i32 %b, i32 %c, i32 %d) "zero-call-used-regs"="used" {
; DIRECT-LABEL: direct_tail:
; DIRECT:       vcvt.s32.f32 s0, s0
; DIRECT-DAG:   mov{{(\.w)?}} r12, #0
; DIRECT-DAG:   vmov r0, s0
; DIRECT:       vmov s0, r12
; DIRECT-NEXT:  b{{(\.w)?}} callee
  %x = fptosi float %a to i32
  %r = tail call i32 @callee(i32 %x, i32 %b, i32 %c, i32 %d)
  ret i32 %r
}
