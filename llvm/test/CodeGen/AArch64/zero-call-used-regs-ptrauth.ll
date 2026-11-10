; RUN: llc -mtriple=aarch64-linux-gnu -mattr=+pauth -O0 -verify-machineinstrs < %s | FileCheck %s
; RUN: llc -mtriple=aarch64-linux-gnu -mattr=+pauth -O2 -verify-machineinstrs < %s | FileCheck %s
; RUN: llc -mtriple=arm64e-apple-darwin -O2 -verify-machineinstrs < %s | FileCheck %s
; RUN: llc -mtriple=aarch64-linux-gnu -mattr=+pauth -stop-after=prolog-epilog < %s | FileCheck %s --check-prefix=PEI

declare void @callee()

; Retaining the X16 and X17 clears must not make both registers unavailable to
; the return-address authentication check at the tail call.
define void @tail_direct() #0 {
; CHECK-LABEL: tail_direct:
; CHECK-DAG: mov x16, #0
; CHECK-DAG: mov x17, #0
; CHECK: eor x16, x30, x30, lsl #1
; CHECK-NEXT: tbz x16, #62,
; CHECK-NEXT: brk #0xc471
; CHECK: b {{_?}}callee
; PEI-LABEL: name: tail_direct
; PEI: hasFakeUses: true
; PEI: FAKE_USE {{.*}}implicit $x16, implicit $x17
; PEI-NEXT: TCRETURNdi @callee, 0,
; PEI-NOT: implicit $x16
; PEI-NOT: implicit $x17
  call void asm sideeffect "", "~{lr}"()
  musttail call void @callee()
  ret void
}

; The indirect call target in X16 is a genuine use. Authentication must use X17
; while the argument in X0 and the target both survive clearing.
define void @tail_indirect(ptr %target) #0 "branch-target-enforcement" {
; CHECK-LABEL: tail_indirect:
; CHECK: mov x16, x0
; CHECK-NOT: mov x0, #0
; CHECK-NOT: mov x16, #0
; CHECK: mov x17, #0
; CHECK-NOT: mov x0, #0
; CHECK-NOT: mov x16, #0
; CHECK: eor x17, x30, x30, lsl #1
; CHECK-NEXT: tbz x17, #62,
; CHECK-NEXT: brk #0xc471
; CHECK: br x16
; PEI-LABEL: name: tail_indirect
; PEI: hasFakeUses: true
; PEI: FAKE_USE {{.*}}implicit $x17
; PEI-NEXT: TCRETURNrix16x17 {{.*}}$x16, 0, {{.*}}implicit $x0
; PEI-NOT: implicit $x17
  call void asm sideeffect "", "~{lr}"()
  musttail call void %target(ptr %target)
  ret void
}

attributes #0 = { "ptrauth-returns" "ptrauth-auth-traps" "zero-call-used-regs"="all" }
