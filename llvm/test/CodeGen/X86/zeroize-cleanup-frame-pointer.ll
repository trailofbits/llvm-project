; RUN: llc -O0 -mtriple=x86_64-unknown-linux-gnu -mattr=+sahf -verify-machineinstrs %s -o - | FileCheck %s
; RUN: llc -O2 -mtriple=x86_64-unknown-linux-gnu -mattr=+sahf -verify-machineinstrs %s -o - | FileCheck %s
; RUN: llc -O2 -mtriple=x86_64-unknown-linux-gnu -mattr=+sahf -verify-machineinstrs -stop-after=prolog-epilog %s -o - | FileCheck %s --check-prefix=MIR
;
; RBP is saved separately from CSI. Both exits switch to the retained SP-based
; CFA before restoring it; the resume must keep that rule after clearing its slot.
; CHECK-LABEL: frame_pointer:
; CHECK: .cfi_offset %rbp, -16
; CHECK: .cfi_def_cfa_register %rbp
; CHECK: callq may_throw
; CHECK: .cfi_def_cfa %rsp, [[#CFA:]]
; CHECK: movq [[#CFA-16]](%rsp), %rbp
; CHECK-NEXT: .cfi_restore %rbp
; CHECK: movq $0, (%rsp)
; CHECK: movq $0, [[#CFA-16]](%rsp)
; CHECK: .cfi_def_cfa %rsp, 8
; CHECK: retq
; CHECK: .cfi_def_cfa %rbp, 16
; CHECK: .cfi_offset %rbp, -16
; CHECK: callq clean
; CHECK: .cfi_def_cfa %rsp, [[#CFA]]
; CHECK: movq [[#CFA-16]](%rsp), %rbp
; CHECK-NEXT: .cfi_restore %rbp
; CHECK: movq $0, (%rsp)
; CHECK: movq $0, [[#CFA-16]](%rsp)
; CHECK-NOT: .cfi_
; CHECK-NOT: %rbp
; CHECK-NOT: %rsp
; CHECK: sahf
; CHECK-NEXT: callq _Unwind_Resume
;
; MIR: CALL64pcrel32{{.*}}@_Unwind_Resume{{.*}}implicit $rbp

declare i32 @__gxx_personality_v0(...)
declare void @may_throw()
declare void @clean()

define i32 @frame_pointer(i32 %result) "zero-call-used-regs"="all" "zeroize-stack"="used" "zeroize-flags" "frame-pointer"="all" personality ptr @__gxx_personality_v0 {
  %slot = alloca i32, align 4
  store volatile i32 42, ptr %slot
  invoke void @may_throw() to label %normal unwind label %cleanup
normal:
  ret i32 %result
cleanup:
  %exception = landingpad {ptr, i32} cleanup
  call void @clean()
  resume {ptr, i32} %exception
}
