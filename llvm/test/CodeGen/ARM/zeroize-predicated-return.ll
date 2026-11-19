; RUN: llc -O2 -mtriple=armv7-none-eabi -verify-machineinstrs -stop-before=prolog-epilog %s -o %t.arm.mir
; RUN: llc -verify-machineinstrs -run-pass=if-converter %t.arm.mir -o %t.arm.pred.mir
; RUN: FileCheck %s --check-prefix=ARM-PRED < %t.arm.pred.mir
; RUN: llc -O0 -verify-machineinstrs -start-before=prolog-epilog %t.arm.pred.mir -o - | FileCheck %s --check-prefix=ARM
; RUN: llc -O2 -mtriple=thumbv7m-none-eabi -verify-machineinstrs -stop-before=prolog-epilog %s -o %t.thumb.mir
; RUN: llc -verify-machineinstrs -run-pass=if-converter %t.thumb.mir -o %t.thumb.pred.mir
; RUN: FileCheck %s --check-prefix=THUMB-PRED < %t.thumb.pred.mir
; RUN: llc -O0 -verify-machineinstrs -start-before=prolog-epilog %t.thumb.pred.mir -o - | FileCheck %s --check-prefix=THUMB
; RUN: sed 's/"zero-call-used-regs"="used-gpr"/"zeroize-stack"="used"/' %s > %t.stack.ll
; RUN: llc -O2 -mtriple=armv7-none-eabi -verify-machineinstrs -stop-before=prolog-epilog %t.stack.ll -o %t.stack.mir
; RUN: llc -verify-machineinstrs -run-pass=if-converter %t.stack.mir -o %t.stack.pred.mir
; RUN: llc -O0 -verify-machineinstrs -start-before=prolog-epilog %t.stack.pred.mir -o - | FileCheck %s --check-prefix=STACK

; ARM normally if-converts after PEI. Feed its actual post-RA output to PEI to
; exercise both the logical fallthrough and the explicit continuation branch.
; The cold path still receives the public argument and has an allocated frame.
; ARM-PRED-LABEL: name: public_cold
; ARM-PRED: BX_RET 0 {{.*}}$cpsr
; ARM-LABEL: public_cold:
; ARM: sub sp, sp, #32
; ARM: mov r0, #17
; ARM: bne [[WORK:\.LBB[0-9_]+]]
; ARM: add sp, sp, #32
; ARM: mov r1, #0
; ARM: pop {{.*}}pc}
; ARM: [[WORK]]:
; ARM: str r1, [sp]
; ARM: bl public_work
; ARM: ldr r0, [sp]
; ARM: add sp, sp, #32
; ARM: mov r1, #0
; ARM: pop {{.*}}pc}

; The stack-only prologue owns 32 local bytes plus two four-byte saves. The
; early return must restore caller state, clear all ten words and release SP.
; STACK-LABEL: public_cold:
; STACK: push {r11, lr}
; STACK: sub sp, sp, #32
; STACK: mov r0, #17
; STACK: bne [[WORK:\.LBB[0-9_]+]]
; STACK: add r1, sp, #36
; STACK-NEXT: ldr lr, [r1]
; STACK-NEXT: add r1, sp, #32
; STACK-NEXT: ldr r11, [r1]
; STACK-NEXT: mov r1, sp
; STACK-NEXT: mov r2, #0
; STACK-NEXT: str r2, [r1]
; STACK-NEXT: str r2, [r1, #4]
; STACK-NEXT: str r2, [r1, #8]
; STACK-NEXT: str r2, [r1, #12]
; STACK-NEXT: str r2, [r1, #16]
; STACK-NEXT: str r2, [r1, #20]
; STACK-NEXT: str r2, [r1, #24]
; STACK-NEXT: str r2, [r1, #28]
; STACK-NEXT: str r2, [r1, #32]
; STACK-NEXT: str r2, [r1, #36]
; STACK-NEXT: add r1, sp, #40
; STACK-NEXT: mov sp, r1
; STACK: bx lr
; STACK: [[WORK]]:
; STACK: str r1, [sp]
; STACK: bl public_work
; STACK: ldr r0, [sp]
; STACK: add r1, sp, #40
; STACK-NEXT: mov sp, r1
; STACK: bx lr

; THUMB-PRED-LABEL: name: public_switch
; THUMB-PRED: tBX_RET 1 {{.*}}$cpsr
; THUMB-PRED-NEXT: t2B %bb.
; THUMB-LABEL: public_switch:
; THUMB: cmp r0, #2
; THUMB: beq [[TWO:\.LBB[0-9_]+]]
; THUMB: movs r1, #0
; THUMB: pop {{.*}}pc}
; THUMB: [[TWO]]:
; THUMB: b [[CALL:\.LBB[0-9_]+]]
; THUMB: str r0, [r1]
; THUMB: movs r1, #0
; THUMB: pop {{.*}}pc}
; THUMB: [[CALL]]:
; THUMB: bl public_a
; THUMB: movs r0, #39

declare void @public_work(ptr) nounwind
declare void @public_a() nounwind
declare void @public_b() nounwind

define i32 @public_cold(i32 %x, i32 %y) #0 {
entry:
  %a = alloca [32 x i8], align 8
  %take = icmp eq i32 %x, 0
  br i1 %take, label %early, label %work, !prof !0
early:
  ret i32 17
work:
  store volatile i32 %y, ptr %a
  call void @public_work(ptr %a)
  %r = load volatile i32, ptr %a
  ret i32 %r
}

define i32 @public_switch(i32 %x, ptr %p) #0 {
entry:
  switch i32 %x, label %d [i32 0, label %a
                           i32 1, label %b
                           i32 2, label %c]
a:
  store volatile i32 37, ptr %p
  ret i32 17
b:
  call void @public_b()
  ret i32 29
c:
  call void @public_a()
  ret i32 39
d:
  ret i32 %x
}

attributes #0 = { noinline "zero-call-used-regs"="used-gpr" }
!0 = !{!"branch_weights", i32 10000, i32 1}
