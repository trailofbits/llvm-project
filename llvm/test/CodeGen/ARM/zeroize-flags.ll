; RUN: llc -mtriple=thumbv8m.base-none-eabi -mattr=+fp-armv8 -verify-machineinstrs %s -o - | FileCheck %s --check-prefixes=CHECK,M
; RUN: llc -mtriple=armv7-none-eabi -verify-machineinstrs %s -o - | FileCheck %s --check-prefixes=CHECK,ARM
; RUN: llc -mtriple=thumbv7-none-eabi -verify-machineinstrs %s -o - | FileCheck %s --check-prefixes=CHECK,ARM
; RUN: llc -mtriple=thumbv6m-none-eabi -verify-machineinstrs %s -o - | FileCheck %s --check-prefixes=CHECK,M
; RUN: llc -mtriple=thumbv7m-none-eabi -verify-machineinstrs %s -o - | FileCheck %s --check-prefixes=CHECK,M
; RUN: llc -mtriple=thumbv7em-none-eabi -verify-machineinstrs %s -o - | FileCheck %s --check-prefixes=CHECK,DSP
; RUN: llc -mtriple=armv7-none-eabi -O0 -verify-machineinstrs %s -o - | FileCheck %s --check-prefixes=CHECK,ARM
; RUN: llc -mtriple=thumbv6m-none-eabi -O0 -verify-machineinstrs %s -o - | FileCheck %s --check-prefixes=CHECK,M
; RUN: llc -mtriple=armv7-none-eabi -filetype=obj %s -o /dev/null
; RUN: llc -mtriple=thumbv7-none-eabi -filetype=obj %s -o /dev/null
; RUN: llc -mtriple=thumbv6m-none-eabi -filetype=obj %s -o /dev/null
; RUN: llc -mtriple=thumbv7em-none-eabi -filetype=obj %s -o /dev/null

; The return value in r0 survives; the flags zero source is itself zeroed.
define i32 @flags_only(i32 returned %x) "zeroize-flags" {
; CHECK-LABEL: flags_only:
; CHECK: mov{{(s|w|\.w)?}} r1, #0
; ARM: uadd8 r1, r1, r1
; ARM-NEXT: msr APSR_nzcvq, r1
; M: msr apsr{{(_nzcvq)?}}, r1
; DSP: msr apsr_nzcvqg, r1
; CHECK-NEXT: bx lr
  ret i32 %x
}

define i32 @skip(i32 returned %x) "zeroize-flags" "zero-call-used-regs"="skip" {
; CHECK-LABEL: skip:
; CHECK: mov{{(s|w|\.w)?}} r1, #0
; ARM: uadd8 r1, r1, r1
; ARM-NEXT: msr APSR_nzcvq, r1
; M: msr apsr{{(_nzcvq)?}}, r1
; DSP: msr apsr_nzcvqg, r1
; CHECK-NEXT: bx lr
  ret i32 %x
}

; Even a used mode selecting no registers must supply a cleared scratch.
define i32 @used(i32 returned %x) "zeroize-flags" "zero-call-used-regs"="used-gpr" {
; CHECK-LABEL: used:
; CHECK: mov{{(s|w|\.w)?}} r1, #0
; ARM: uadd8 r1, r1, r1
; ARM-NEXT: msr APSR_nzcvq, r1
; M: msr apsr{{(_nzcvq)?}}, r1
; DSP: msr apsr_nzcvqg, r1
; CHECK-NEXT: bx lr
  ret i32 %x
}

; The stack loop's compare and every scratch clear precede the final MSR.
define i64 @stack_and_flags(i64 returned %x) "zeroize-stack" "zeroize-flags" {
; CHECK-LABEL: stack_and_flags:
; CHECK: str
; CHECK: cmp
; CHECK: bne
; CHECK: mov{{(s|w|\.w)?}} r2, #0
; ARM: uadd8 r2, r2, r2
; ARM-NEXT: msr APSR_nzcvq, r2
; M: msr apsr{{(_nzcvq)?}}, r2
; DSP: msr apsr_nzcvqg, r2
; CHECK-NEXT: bx lr
  %p = alloca [128 x i8], align 4
  store volatile i8 42, ptr %p
  ret i64 %x
}

; A return that restores saved registers can follow MSR without rewriting flags.
declare void @effect()
define void @saved() "zeroize-flags" {
; CHECK-LABEL: saved:
; CHECK: bl effect
; CHECK: mov{{(s|w|\.w)?}} r0, #0
; ARM: uadd8 r0, r0, r0
; ARM-NEXT: msr APSR_nzcvq, r0
; M: msr apsr{{(_nzcvq)?}}, r0
; DSP: msr apsr_nzcvqg, r0
  call void @effect()
  ret void
}
