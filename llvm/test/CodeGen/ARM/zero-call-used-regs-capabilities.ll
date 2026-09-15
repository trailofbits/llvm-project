; RUN: llc -mtriple=armv7-unknown-linux-gnueabi -pei-print-clearing-sequence %s -o /dev/null 2>&1 | FileCheck %s --implicit-check-not=error:
; RUN: llc -mtriple=armebv7-unknown-linux-gnueabi -pei-print-clearing-sequence %s -o /dev/null 2>&1 | FileCheck %s --implicit-check-not=error:
; RUN: llc -mtriple=thumbv6m-none-eabi -pei-print-clearing-sequence %s -o /dev/null 2>&1 | FileCheck %s --implicit-check-not=error:
; RUN: llc -mtriple=thumbv8m.base-none-eabi -pei-print-clearing-sequence %s -o /dev/null 2>&1 | FileCheck %s --implicit-check-not=error:
; RUN: llc -mtriple=thumbv7m-none-eabi -pei-print-clearing-sequence %s -o /dev/null 2>&1 | FileCheck %s --implicit-check-not=error:
; RUN: llc -mtriple=thumbv8m.main-none-eabi -mattr=+fp-armv8d16sp -pei-print-clearing-sequence %s -o /dev/null 2>&1 | FileCheck %s --implicit-check-not=error:
; RUN: llc -mtriple=thumbv7-unknown-linux-gnueabihf -mattr=+neon -pei-print-clearing-sequence %s -o /dev/null 2>&1 | FileCheck %s --implicit-check-not=error:
; RUN: llc -mtriple=thumbv8.1m.main-none-eabi -mattr=+mve -pei-print-clearing-sequence %s -o /dev/null 2>&1 | FileCheck %s --implicit-check-not=error:

; Register clearing is supported across instruction modes and FP/vector
; configurations. Stack clearing remains an independent, unsupported capability.

; CHECK-LABEL: clearing sequence for function 'used_gpr':
; CHECK: return: clear-stack=not-requested clear-registers=emitted clear-flags=not-requested
define i32 @used_gpr(i32 %x) "zero-call-used-regs"="used-gpr" {
  ret i32 %x
}

; CHECK-LABEL: clearing sequence for function 'all':
; CHECK: return: clear-stack=not-requested clear-registers=emitted clear-flags=not-requested
define i32 @all(i32 %x) "zero-call-used-regs"="all" {
  ret i32 %x
}

; "skip" asks for nothing, so there is nothing to report.
; CHECK-LABEL: clearing sequence for function 'skip':
; CHECK: return: clear-stack=not-requested clear-registers=not-requested clear-flags=not-requested
define i32 @skip(i32 %x) "zero-call-used-regs"="skip" {
  ret i32 %x
}
