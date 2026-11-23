; RUN: llc -mtriple=aarch64-unknown-linux-gnu -verify-machineinstrs < %s | FileCheck %s
; RUN: llc -mtriple=aarch64-unknown-linux-gnu -verify-machineinstrs -filetype=obj < %s -o %t
; RUN: llvm-dwarfdump --eh-frame %t | FileCheck %s --check-prefix=CFI
; RUN: not llc -mtriple=aarch64-unknown-linux-gnu -mattr=+sve < %s -o /dev/null 2>&1 | FileCheck %s --check-prefix=REJECT
; RUN: sed 's/__gxx_personality_v0/custom_personality/g' %s > %t-unknown.ll
; RUN: not llc -mtriple=aarch64-unknown-linux-gnu %t-unknown.ll -o /dev/null 2>&1 | FileCheck %s --check-prefix=REJECT
; RUN: llc -mtriple=aarch64-unknown-linux-gnu -save-temp-labels -stop-after=prolog-epilog %s -o %t.mir
; RUN: sed 's/\.Lzeroize_resume_0/.Lwrong_continuation/g' %t.mir > %t-wrong.mir
; RUN: not llc -mtriple=aarch64-unknown-linux-gnu -verify-machineinstrs -start-after=prolog-epilog %t-wrong.mir -o /dev/null 2>&1 | FileCheck %s --check-prefix=WRONG
; REJECT: AArch64 stack clearing does not support this frame, calling convention, or exit
; WRONG: unsupported final unwind protocol
;
; Escaping cleanups retain the original erased allocation. A separate local
; thunk carries only restored caller context and a constant continuation.

declare i32 @__gxx_personality_v0(...)
declare void @action(i32)
declare void @event(i32) nounwind

; CHECK-LABEL: fixed48:
; CHECK: .cfi_def_cfa_offset 48
; CHECK: adrp x1, .Lzeroize_resume_[[CONT48:[0-9]+]]
; CHECK-NEXT: add x1, x1, :lo12:.Lzeroize_resume_[[CONT48]]
; CHECK: msr NZCV, xzr
; CHECK-NEXT: b .Lzeroize_resume_thunk[[THUNK48:[0-9]+]]
; CHECK: .cfi_def_cfa wsp, 48
; CHECK: .cfi_escape 0x16, 0x1e, 0x03, 0x85, 0x00, 0x06, 0x16, 0x15, 0x03, 0x85, 0x08, 0x06
; CHECK-NEXT: hint #0
; CHECK-NEXT: .Lzeroize_resume_[[CONT48]]:
; CHECK-NEXT: brk #0

define void @fixed48(i32 %value) #0 personality ptr @__gxx_personality_v0 {
entry:
  call void asm sideeffect "", "~{x19},~{x20},~{v8}"()
  invoke void @action(i32 %value) to label %normal unwind label %cleanup
normal:
  call void @event(i32 1)
  ret void
cleanup:
  %exception = landingpad {ptr, i32} cleanup
  call void @event(i32 1)
  resume {ptr, i32} %exception
}

; CHECK-LABEL: fixed64:
; CHECK: .cfi_def_cfa_offset 64
; CHECK: ldr x21,
; CHECK: adrp x1, .Lzeroize_resume_[[CONT64:[0-9]+]]
; CHECK-NEXT: add x1, x1, :lo12:.Lzeroize_resume_[[CONT64]]
; CHECK: msr NZCV, xzr
; CHECK-NEXT: b .Lzeroize_resume_thunk[[THUNK64:[0-9]+]]
; CHECK: .Lzeroize_resume_[[CONT64]]:

define void @fixed64(i32 %value) #0 personality ptr @__gxx_personality_v0 {
entry:
  call void asm sideeffect "mov x21, #103", "~{x19},~{x20},~{x21},~{x22},~{v8}"()
  invoke void @action(i32 %value) to label %normal unwind label %cleanup
normal:
  call void @event(i32 1)
  ret void
cleanup:
  %exception = landingpad {ptr, i32} cleanup
  call void @event(i32 1)
  resume {ptr, i32} %exception
}

; CHECK-LABEL: two_cleanups:
; CHECK: adrp x1, .Lzeroize_resume_[[SHARED:[0-9]+]]
; CHECK: b .Lzeroize_resume_thunk[[THUNK48]]
; CHECK: .Lzeroize_resume_[[SHARED]]:
; CHECK-NOT: .Lzeroize_resume_[[SHARED]]:

define void @two_cleanups(i1 %side) #0 personality ptr @__gxx_personality_v0 {
entry:
  call void asm sideeffect "", "~{x19},~{x20},~{v8}"()
  br i1 %side, label %left, label %right
left:
  invoke void @action(i32 1) to label %normal unwind label %cleanup1
right:
  invoke void @action(i32 2) to label %normal unwind label %cleanup2
normal:
  ret void
cleanup1:
  %exception1 = landingpad {ptr, i32} cleanup
  call void @event(i32 1)
  resume {ptr, i32} %exception1
cleanup2:
  %exception2 = landingpad {ptr, i32} cleanup
  call void @event(i32 2)
  resume {ptr, i32} %exception2
}

; The two extents need different transient CFA rows. Neither helper allocates
; any bytes inside the protected function's original allocation.
; CHECK: .Lzeroize_resume_thunk[[THUNK48]]:
; CHECK-NEXT: .cfi_startproc
; CHECK-NEXT: .cfi_def_cfa_offset 48
; CHECK-NEXT: sub sp, sp, #32
; CHECK-NEXT: .cfi_def_cfa_offset 80
; CHECK-NEXT: stp x30, x21, [sp]
; CHECK-NEXT: .cfi_offset w30, -80
; CHECK-NEXT: .cfi_offset w21, -72
; CHECK-NEXT: stp xzr, x1, [sp, #16]
; CHECK-NEXT: mov x21, sp
; CHECK-NEXT: .cfi_def_cfa_offset 32
; CHECK-NEXT: .cfi_offset w30, -8
; CHECK-NEXT: .cfi_same_value w21
; CHECK-NEXT: mov x1, xzr
; CHECK-NEXT: bl _Unwind_Resume
; CHECK-NEXT: brk #0
; CHECK-NEXT: .cfi_endproc
; CHECK: .Lzeroize_resume_thunk[[THUNK64]]:
; CHECK-NEXT: .cfi_startproc
; CHECK-NEXT: .cfi_def_cfa_offset 64
; CHECK-NEXT: sub sp, sp, #32
; CHECK-NEXT: .cfi_def_cfa_offset 96
; CHECK-NEXT: stp x30, x21, [sp]
; CHECK-NEXT: .cfi_offset w30, -96
; CHECK-NEXT: .cfi_offset w21, -88

; CFI: DW_CFA_def_cfa_offset: +48
; CFI: DW_CFA_def_cfa_offset: +80
; CFI: DW_CFA_offset: W30 -80
; CFI: DW_CFA_offset: W21 -72
; CFI: DW_CFA_def_cfa_offset: +32
; CFI: DW_CFA_offset: W30 -8
; CFI: DW_CFA_same_value: W21
; CFI: DW_CFA_val_expression: W30 DW_OP_breg21 W21+0, DW_OP_deref
; CFI: DW_CFA_val_expression: W21 DW_OP_breg21 W21+8, DW_OP_deref

attributes #0 = { uwtable "frame-pointer"="all" "zeroize-stack"="used" "zeroize-flags" "zero-call-used-regs"="all" }
