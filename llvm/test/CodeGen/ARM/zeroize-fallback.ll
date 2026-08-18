; Exit scope and unreadable modes are resolved before asking the target.

; RUN: split-file %s %t
; RUN: llc -mtriple=armv7-unknown-linux-gnueabi -verify-machineinstrs -pei-print-clearing-sequence %t/exits.ll -o /dev/null 2>&1 | FileCheck --check-prefix=SEQ %s
; RUN: llc -mtriple=armv7-unknown-linux-gnueabi -verify-machineinstrs %t/unknown.ll -o - | FileCheck --check-prefix=UNKNOWN %s
; RUN: llc -mtriple=armv7-unknown-linux-gnueabi -verify-machineinstrs %t/empty.ll -o - | FileCheck --check-prefix=EMPTY %s
; RUN: llc -mtriple=armv7-unknown-linux-gnueabi -verify-machineinstrs %t/skip.ll -o - | FileCheck --check-prefix=SKIP %s

;--- exits.ll
@g = external global i32

declare void @llvm.trap()

; A supervisor call written as inline asm ends the block; whether control
; comes back is not something the compiler can decide.
; SEQ-LABEL: clearing sequence for function 'opaque_asm':
; SEQ-NEXT:  %bb.0 unknown: clear-stack=not-requested clear-registers=not-requested clear-flags=unimplemented
; SEQ-NEXT:  end clearing sequence for function 'opaque_asm'
define void @opaque_asm(i32 %a, i32 %b) {
  %s = add i32 %a, %b
  store i32 %s, ptr @g
  call void asm sideeffect "svc #0", "~{memory}"()
  unreachable
}

; A trap stays out of scope.
; SEQ-LABEL: clearing sequence for function 'traps':
; SEQ-NEXT:  end clearing sequence for function 'traps'
define void @traps() {
  call void @llvm.trap()
  unreachable
}

;--- unknown.ll
; An unreadable mode widens to "all", clearing the registers the exit can spare.
; UNKNOWN-LABEL: unrecognized_mode:
; UNKNOWN:         vmov.i32 q0, #0x0
; UNKNOWN:         mov r2, #0
; UNKNOWN:         mov r3, #0
; UNKNOWN:         mov r12, #0
; UNKNOWN:         vmov.i32 q15, #0x0
; UNKNOWN:         bx lr
define i32 @unrecognized_mode(i32 %x) "zero-call-used-regs"="a-mode-from-the-future" {
  ret i32 %x
}

;--- empty.ll
; An empty value also widens to "all".
; EMPTY-LABEL: empty_mode:
; EMPTY:         vmov.i32 q0, #0x0
; EMPTY:         mov r2, #0
; EMPTY:         mov r3, #0
; EMPTY:         mov r12, #0
; EMPTY:         vmov.i32 q15, #0x0
; EMPTY:         bx lr
define i32 @empty_mode(i32 %x) "zero-call-used-regs"="" {
  ret i32 %x
}

;--- skip.ll
; "skip" is honored and clears no registers.
; SKIP-LABEL: skips_explicitly:
; SKIP-NOT:     mov r{{[0-9]+}}, #0
; SKIP-NOT:     vmov
; SKIP:         bx lr
define i32 @skips_explicitly(i32 %x) "zero-call-used-regs"="skip" {
  ret i32 %x
}
