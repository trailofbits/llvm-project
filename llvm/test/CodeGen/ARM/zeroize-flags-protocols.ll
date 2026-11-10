; RUN: split-file %s %t
; RUN: not llc -mtriple=armv7-none-eabi %t/interrupt.ll -o /dev/null 2>&1 | FileCheck %s
; RUN: not llc -mtriple=armv7-none-eabi %t/cleanup.ll -o /dev/null 2>&1 | FileCheck %s
; RUN: not llc -mtriple=thumbv7-none-eabi -mattr=-dsp %t/ordinary.ll -o /dev/null 2>&1 | FileCheck %s
; RUN: not --crash llc -mtriple=armv7-none-eabi %t/musttail.ll -o /dev/null 2>&1 | FileCheck %s --check-prefix=TAIL
; CHECK: error: {{.*}}"zeroize-flags" is not supported by this target or exit protocol
; TAIL: failed to perform tail call elimination on a call site marked musttail

;--- interrupt.ll
define arm_aapcscc void @irq() "interrupt"="IRQ" "zeroize-flags" { ret void }
;--- cleanup.ll
declare void @_Unwind_Resume(ptr)
define void @cleanup(ptr %exn) "zeroize-flags" {
  call void @_Unwind_Resume(ptr %exn)
  unreachable
}
;--- ordinary.ll
define void @ordinary() "zeroize-flags" { ret void }
;--- musttail.ll
declare i32 @callee(i32)
define i32 @mandatory(i32 %x) "zeroize-flags" {
  %r = musttail call i32 @callee(i32 %x)
  ret i32 %r
}
