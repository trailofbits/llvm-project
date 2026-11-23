; RUN: llc -mtriple=armv7-linux-gnueabihf -mattr=+neon -verify-machineinstrs < %s | FileCheck %s
; RUN: llc -mtriple=thumbv7-linux-gnueabihf -mattr=+neon -verify-machineinstrs < %s | FileCheck %s
; RUN: llc -mtriple=armv7-linux-gnueabihf -mattr=+neon -verify-machineinstrs -filetype=obj < %s -o %t.o
; RUN: llvm-readobj --unwind %t.o | FileCheck %s --check-prefix=UNWIND
; RUN: sed 's/\[6 x i32\]/[54 x i32]/g' %s | llc -mtriple=armv7-linux-gnueabihf \
; RUN:   -mattr=+neon -verify-machineinstrs | FileCheck %s --check-prefix=LIMIT
; RUN: sed 's/\[6 x i32\]/[56 x i32]/g' %s > %t.large
; RUN: not llc -mtriple=armv7-linux-gnueabihf -mattr=+neon %t.large -o /dev/null 2>&1 \
; RUN:   | FileCheck %s --check-prefix=FRAME-ERROR
; RUN: sed 's/"frame-pointer"="none"/safestack/' %s > %t.safestack
; RUN: not llc -mtriple=armv7-linux-gnueabihf -mattr=+neon %t.safestack -o /dev/null 2>&1 \
; RUN:   | FileCheck %s --check-prefix=ERROR
; RUN: sed 's/"frame-pointer"="none"/"function-instrument"="xray-always"/' %s > %t.xray
; RUN: not llc -mtriple=armv7-linux-gnueabihf -mattr=+neon %t.xray -o /dev/null 2>&1 \
; RUN:   | FileCheck %s --check-prefix=ERROR
; RUN: sed 's/@cleanup(i32 %value)/@cleanup(i32 %value, ...)/' %s > %t.vararg
; RUN: not llc -mtriple=armv7-linux-gnueabihf -mattr=+neon %t.vararg -o /dev/null 2>&1 \
; RUN:   | FileCheck %s --check-prefix=ERROR
; RUN: sed 's/landingpad { ptr, i32 } cleanup/landingpad { ptr, i32 } cleanup catch ptr null/' %s > %t.catch
; RUN: not llc -mtriple=armv7-linux-gnueabihf -mattr=+neon %t.catch -o /dev/null 2>&1 \
; RUN:   | FileCheck %s --check-prefix=ERROR
; RUN: sed 's/landingpad { ptr, i32 } cleanup/landingpad { ptr, i32 } cleanup filter [0 x ptr] zeroinitializer/' %s > %t.filter
; RUN: not llc -mtriple=armv7-linux-gnueabihf -mattr=+neon %t.filter -o /dev/null 2>&1 \
; RUN:   | FileCheck %s --check-prefix=ERROR
; RUN: sed 's/__gxx_personality_v0/custom_personality/g' %s > %t.custom
; RUN: not llc -mtriple=armv7-linux-gnueabihf -mattr=+neon %t.custom -o /dev/null 2>&1 \
; RUN:   | FileCheck %s --check-prefix=ERROR

declare void @action()
declare void @cleanup_event() nounwind
declare i32 @__gxx_personality_v0(...)

define i32 @cleanup(i32 %value) #0 personality ptr @__gxx_personality_v0 {
entry:
  %words = alloca [6 x i32], align 4
  %slot = getelementptr [6 x i32], ptr %words, i32 0, i32 1
  store volatile i32 %value, ptr %slot
  call void asm sideeffect "", "r,~{r4},~{memory}"(ptr %words)
  invoke void @action() to label %return unwind label %cleanup
return:
  %result = load volatile i32, ptr %slot
  call void @cleanup_event()
  ret i32 %result
cleanup:
  %exception = landingpad { ptr, i32 } cleanup
  call void @cleanup_event()
  resume { ptr, i32 } %exception
}

attributes #0 = { "zeroize-stack"="used" "zero-call-used-regs"="all-gpr" "zeroize-flags" "frame-pointer"="none" }

; CHECK-LABEL: cleanup:
; CHECK: .save {r4, lr}
; CHECK: .pad #24
; CHECK: bx lr
; CHECK: bl cleanup_event
; CHECK: ldr{{.*}} lr,
; CHECK: ldr{{.*}} r4,
; CHECK: str{{.*}} r3, [r0]
; CHECK: str{{.*}} r3, [r0, #28]
; CHECK: movw r1, :lower16:(.Larm_zeroize_continuation_0-
; CHECK: movt r1, :upper16:(.Larm_zeroize_continuation_0-
; CHECK: movw r12, :lower16:(.Larm_zeroize_carrier_0-
; CHECK: movt r12, :upper16:(.Larm_zeroize_carrier_0-
; CHECK: msr APSR_nzcvq,
; CHECK-NEXT: bx r12
; CHECK: .Larm_zeroize_continuation_0:
; CHECK: .personality .Larm_zeroize_personality_0
; CHECK: .Larm_zeroize_carrier_0:
; CHECK: sub sp, sp, #16
; CHECK: str r4, [sp]
; CHECK: str lr, [sp, #4]
; CHECK: str r2, [sp, #8]
; CHECK: str r1, [sp, #12]
; CHECK: mov r4, sp
; CHECK: bl __cxa_end_cleanup
; CHECK: .personality .Larm_zeroize_helper_personality_0
; CHECK: .Larm_zeroize_personality_0:
; CHECK: .save {r4, r5, r6, r7, r8, r9, r10, r11, lr}
; CHECK: .pad #60
; CHECK: bl __gxx_personality_v0
; CHECK: cmp r0, #7
; CHECK: bl _Unwind_VRS_Get
; CHECK: cmp r10, #0
; CHECK: str r9, [sp, #36]
; CHECK: bl __gnu_unwind_frame
; CHECK: ldm r12, {r4, r5, r6, r7, r8, r9, r10, r11, lr}
; CHECK-COUNT-24: str r1, [sp
; CHECK: msr APSR_nzcvq, r1
; CHECK-NEXT: add sp, sp, #96
; CHECK-NEXT: bx lr
; CHECK: .Larm_zeroize_helper_personality_0:
; CHECK: bl _Unwind_VRS_Set
; CHECK: ldm r12, {r4, r5, r6, r7, r8, r9, r10, r11, lr}
; CHECK-COUNT-24: str r1, [sp
; CHECK: msr APSR_nzcvq, r1
; CHECK-NEXT: add sp, sp, #96
; CHECK-NEXT: bx lr
; UNWIND-COUNT-2: vsp = vsp + 60
; LIMIT: .pad #216
; LIMIT: bx r12
; LIMIT: add r8, r9, #240
; FRAME-ERROR: error: {{.*}}ARM cleanup clearing requires the supported SP-based frame recipe
; FRAME-ERROR-NOT: Assertion
; ERROR: error: {{.*}}ARM stack clearing does not support
; ERROR-NOT: Assertion
