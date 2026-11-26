; RUN: llc -mtriple=aarch64-linux-android29 -mattr=+reserve-x18 -verify-machineinstrs %s -o - | FileCheck %s --check-prefix=ASM
; RUN: llc -mtriple=aarch64-linux-android29 -mattr=+reserve-x18 -verify-machineinstrs -filetype=obj %s -o %t
; RUN: llvm-dwarfdump --eh-frame %t | FileCheck %s --check-prefix=CFI
; RUN: not llc -mtriple=aarch64-linux-android28 -mattr=+reserve-x18 %s -o /dev/null 2>&1 | FileCheck %s --check-prefix=REJECT
; RUN: not llc -mtriple=aarch64-linux-gnu -mattr=+reserve-x18 %s -o /dev/null 2>&1 | FileCheck %s --check-prefix=REJECT
; RUN: not llc -mtriple=aarch64-linux-android29 -mattr=+reserve-x18,+sve %s -o /dev/null 2>&1 | FileCheck %s --check-prefix=REJECT
; RUN: llc -mtriple=aarch64-linux-android29 -mattr=+reserve-x18 -save-temp-labels -stop-before=prolog-epilog %s -o %t.mir
; RUN: sed 's/BL @_Unwind_Resume,/BL @_Unwind_Resume + 4,/' %t.mir > %t-offset.mir
; RUN: not llc -mattr=+reserve-x18 -start-before=prolog-epilog %t-offset.mir -o /dev/null 2>&1 | FileCheck %s --check-prefix=REJECT
; RUN: sed '/BL @_Unwind_Resume/s/, implicit \$x0//' %t.mir > %t-arg.mir
; RUN: not llc -mattr=+reserve-x18 -start-before=prolog-epilog %t-arg.mir -o /dev/null 2>&1 | FileCheck %s --check-prefix=REJECT

; RUN: sed '/BL @_Unwind_Resume/s/, implicit \$x0/, implicit undef $x0/' %t.mir > %t-undef.mir
; RUN: not llc -mattr=+reserve-x18 -start-before=prolog-epilog %t-undef.mir -o /dev/null 2>&1 | FileCheck %s --check-prefix=REJECT

; RUN: sed 's/^declare void @_Unwind_Resume(ptr)/define void @_Unwind_Resume(ptr %e) { unreachable }/' %s > %t-local.ll
; RUN: not llc -mtriple=aarch64-linux-android29 -mattr=+reserve-x18 %t-local.ll -o /dev/null 2>&1 | FileCheck %s --check-prefix=REJECT

declare void @_Unwind_Resume(ptr)
declare i32 @__gxx_personality_v0(...)
declare void @callee(ptr)
declare void @cleanup() nounwind

define void @guarded() shadowcallstack uwtable "zeroize-stack"="used" "zeroize-flags" "zero-call-used-regs"="all" personality ptr @__gxx_personality_v0 {
entry:
  %local = alloca [96 x i8], align 16
  call void asm sideeffect "", "~{v8}"()
  invoke void @callee(ptr %local) to label %done unwind label %unwind

done:
  ret void

unwind:
  %exception = landingpad {ptr, i32} cleanup
  call void @cleanup()
  resume {ptr, i32} %exception
}

; The ordinary return must still pop the protected return address from X18.
; ASM-LABEL: guarded:
; ASM: str x30, [x18], #8
; ASM: bl callee
; ASM: ldr x30, [x18, #-8]!
; ASM: ldr d8,
; ASM: stp xzr, xzr,
; ASM: mov v8.d[1], xzr
; ASM: ret
;
; The resume call keeps its physical frame. Zero the frame and leave the
; shadow entry available for the unwinder's step past guarded.
; ASM: bl cleanup
; ASM: .cfi_escape 0x10, 0x1e, 0x02, 0x82, 0x78
; ASM-NOT: ldr x30, [x18
; ASM: stp xzr, xzr,
; ASM-NOT: mov sp,
; ASM-NOT: add sp,
; ASM: mov v8.d[1], xzr
; ASM: msr NZCV, xzr
; ASM-NEXT: bl _Unwind_Resume

; CFI: CFA=WSP+{{[1-9][0-9]*}}: W18=DW_OP_breg18 W18-8, W30=[DW_OP_breg18 W18-8]
; REJECT: AArch64 stack clearing does not support this frame, calling convention, or exit
