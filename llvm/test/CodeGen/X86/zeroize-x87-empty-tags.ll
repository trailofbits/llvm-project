; RUN: split-file %s %t
; RUN: llc -mtriple=x86_64-unknown-linux-gnu -mcpu=x86-64-v2 -verify-machineinstrs %t/returns.ll -o - | FileCheck %s --implicit-check-not=emms
; RUN: not llc -mtriple=x86_64-unknown-linux-gnu -mattr=+sahf,+mmx,-x87 -verify-machineinstrs %t/no-x87.ll -o /dev/null 2>&1 | FileCheck %s --check-prefix=NOX87

;--- returns.ll

define i32 @joint_integer(i32 %result) #0 {
; CHECK-LABEL: joint_integer:
; CHECK:       emms
; CHECK-NEXT:  fldz
; CHECK-COUNT-7: fldz
; CHECK-COUNT-8: fstp %st(0)
; CHECK:       retq
  ret i32 %result
}

define i32 @registers_only(i32 %result) "zero-call-used-regs"="all" {
; CHECK-LABEL: registers_only:
; CHECK:       fldz
; CHECK:       retq
  ret i32 %result
}

define i32 @stack_and_registers(i32 %result) "zero-call-used-regs"="all" "zeroize-stack"="used" {
; CHECK-LABEL: stack_and_registers:
; CHECK:       fldz
; CHECK:       retq
  ret i32 %result
}

; The normal return exports ST(0). The resume exports only the pointer in RDI.
declare i32 @__gxx_personality_v0(...)
declare void @may_throw()

define x86_fp80 @value_or_resume(x86_fp80 %value) #0 personality ptr @__gxx_personality_v0 {
; CHECK-LABEL: value_or_resume:
; CHECK:       fldt
; CHECK-COUNT-7: fldz
; CHECK-NOT:   fldz
; CHECK-COUNT-7: fstp %st(0)
; CHECK-NOT:   fstp %st(0)
; CHECK:       retq
; CHECK:       emms
; CHECK-NEXT:  fldz
; CHECK-COUNT-7: fldz
; CHECK-COUNT-8: fstp %st(0)
; CHECK:       callq _Unwind_Resume
  invoke void @may_throw() to label %normal unwind label %cleanup
normal:
  ret x86_fp80 %value
cleanup:
  %exception = landingpad { ptr, i32 } cleanup
  resume { ptr, i32 } %exception
}

define i32 @no_mmx(i32 %result) #0 "target-features"="-mmx,+x87,+sahf" {
; CHECK-LABEL: no_mmx:
; CHECK:       fldz
; CHECK:       retq
  ret i32 %result
}

define i32 @no_mmx_no_x87(i32 %result) #0 "target-features"="-mmx,-x87,+sahf" {
; CHECK-LABEL: no_mmx_no_x87:
; CHECK-NOT:   fldz
; CHECK:       retq
  ret i32 %result
}

attributes #0 = { "zero-call-used-regs"="all" "zeroize-stack"="used" "zeroize-flags" }

;--- no-x87.ll
; NOX87: error: {{.*}}in function mmx_without_x87{{.*}}this subtarget has no instruction to clear
define i32 @mmx_without_x87(i32 %result) "zero-call-used-regs"="all" "zeroize-stack"="used" "zeroize-flags" {
  ret i32 %result
}
