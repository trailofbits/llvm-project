; RUN: split-file %s %t
; RUN: llc -mtriple=thumbv8m.base-none-eabi -mattr=+fp-armv8 \
; RUN:   -verify-machineinstrs -pei-print-clearing-sequence %t/supported.ll -o /dev/null 2>&1 | \
; RUN:   FileCheck %s --check-prefix=SUPPORTED --implicit-check-not=error:
; RUN: llc -mtriple=thumbv8m.base-none-eabi -mattr=+fp-armv8 -O0 \
; RUN:   -verify-machineinstrs -pei-print-clearing-sequence %t/supported.ll -o /dev/null 2>&1 | \
; RUN:   FileCheck %s --check-prefix=SUPPORTED --implicit-check-not=error:
; RUN: not llc -mtriple=thumbv8m.base-none-eabi -mattr=+fp-armv8 \
; RUN:   -verify-machineinstrs -pei-print-clearing-sequence %t/unsupported.ll -o /dev/null 2>&1 | \
; RUN:   FileCheck %s --check-prefix=REJECTED
; RUN: not llc -mtriple=thumbv8m.base-none-eabi -mattr=+fp-armv8 -O0 \
; RUN:   -verify-machineinstrs -pei-print-clearing-sequence %t/unsupported.ll -o /dev/null 2>&1 | \
; RUN:   FileCheck %s --check-prefix=REJECTED
; RUN: not llc -mtriple=thumbv8m.base-none-eabi -mattr=+fp-armv8 \
; RUN:   -verify-machineinstrs %t/stack.ll -o /dev/null 2>&1 | \
; RUN:   FileCheck %s --check-prefix=STACK

; Thumb-1 cannot clear VFP registers. Missing and skip modes still permit
; scratch-only clearing; explicit GPR modes do not request VFP clearing.
; SUPPORTED-LABEL: clearing sequence for function 'absent':
; SUPPORTED: return: clear-stack=not-requested clear-registers=emitted
; SUPPORTED-SAME: clear-flags=emitted
; SUPPORTED-LABEL: clearing sequence for function 'skip':
; SUPPORTED: return: clear-stack=not-requested clear-registers=emitted
; SUPPORTED-SAME: clear-flags=emitted
; SUPPORTED-LABEL: clearing sequence for function 'used_gpr':
; SUPPORTED: return: clear-stack=not-requested clear-registers=emitted
; SUPPORTED-SAME: clear-flags=emitted
; SUPPORTED-LABEL: clearing sequence for function 'used_gpr_arg':
; SUPPORTED: return: clear-stack=not-requested clear-registers=emitted
; SUPPORTED-SAME: clear-flags=emitted
; SUPPORTED-LABEL: clearing sequence for function 'all_gpr':
; SUPPORTED: return: clear-stack=not-requested clear-registers=emitted
; SUPPORTED-SAME: clear-flags=emitted
; SUPPORTED-LABEL: clearing sequence for function 'all_gpr_arg':
; SUPPORTED: return: clear-stack=not-requested clear-registers=emitted
; SUPPORTED-SAME: clear-flags=emitted

; Present-empty, valueless, and unknown modes mean all, not skip. An
; unsupported register clear cannot provide zeroed scratch to the flags step.
; REJECTED: error: {{.*}}"zero-call-used-regs" is not supported by this target
; REJECTED-LABEL: clearing sequence for function 'empty':
; REJECTED: return: clear-stack=not-requested clear-registers=unsupported
; REJECTED-SAME: clear-flags=unsupported
; REJECTED: error: {{.*}}"zero-call-used-regs" is not supported by this target
; REJECTED-LABEL: clearing sequence for function 'valueless':
; REJECTED: return: clear-stack=not-requested clear-registers=unsupported
; REJECTED-SAME: clear-flags=unsupported
; REJECTED: error: {{.*}}"zero-call-used-regs" is not supported by this target
; REJECTED-LABEL: clearing sequence for function 'unknown':
; REJECTED: return: clear-stack=not-requested clear-registers=unsupported
; REJECTED-SAME: clear-flags=unsupported
; REJECTED: error: {{.*}}"zero-call-used-regs" is not supported by this target
; REJECTED-LABEL: clearing sequence for function 'all':
; REJECTED: return: clear-stack=not-requested clear-registers=unsupported
; REJECTED-SAME: clear-flags=unsupported

; The same distinction applies to scratch for stack-only requests. No frame
; is needed to test the function-level capability check.
; STACK: error: {{.*}}"zero-call-used-regs" is not supported by this target
; STACK: error: {{.*}}"zero-call-used-regs" is not supported by this target
; STACK: error: {{.*}}"zero-call-used-regs" is not supported by this target

;--- supported.ll
define void @absent() "zeroize-flags" { ret void }
define void @skip() "zeroize-flags" "zero-call-used-regs"="skip" { ret void }
define void @used_gpr() "zeroize-flags" "zero-call-used-regs"="used-gpr" { ret void }
define void @used_gpr_arg() "zeroize-flags" "zero-call-used-regs"="used-gpr-arg" { ret void }
define void @all_gpr() "zeroize-flags" "zero-call-used-regs"="all-gpr" { ret void }
define void @all_gpr_arg() "zeroize-flags" "zero-call-used-regs"="all-gpr-arg" { ret void }

;--- unsupported.ll
define void @empty() "zeroize-flags" "zero-call-used-regs"="" { ret void }
define void @valueless() "zeroize-flags" "zero-call-used-regs" { ret void }
define void @unknown() "zeroize-flags" "zero-call-used-regs"="unknown" { ret void }
define void @all() "zeroize-flags" "zero-call-used-regs"="all" { ret void }

;--- stack.ll
define void @empty_stack() "zeroize-stack" "zero-call-used-regs"="" { unreachable }
define void @valueless_stack() "zeroize-stack" "zero-call-used-regs" { unreachable }
define void @unknown_stack() "zeroize-stack" "zero-call-used-regs"="unknown" { unreachable }
