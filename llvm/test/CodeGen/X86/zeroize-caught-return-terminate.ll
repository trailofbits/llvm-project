; RUN: split-file %s %t
; RUN: llc -O0 -mtriple=x86_64-unknown-linux-gnu -mattr=+sahf -verify-machineinstrs %t/terminate.ll -o - | FileCheck %s
; RUN: llc -O2 -mtriple=x86_64-unknown-linux-gnu -mattr=+sahf -verify-machineinstrs %t/terminate.ll -o - | FileCheck %s
; RUN: not llc -O0 -mtriple=x86_64-unknown-linux-gnu -mattr=+sahf %t/may-unwind.ll -o /dev/null 2>&1 | FileCheck %s --check-prefix=REJECT
; RUN: not llc -O2 -mtriple=x86_64-unknown-linux-gnu -mattr=+sahf %t/may-unwind.ll -o /dev/null 2>&1 | FileCheck %s --check-prefix=REJECT
; RUN: not llc -O0 -mtriple=x86_64-unknown-linux-gnu -mattr=+sahf %t/may-return.ll -o /dev/null 2>&1 | FileCheck %s --check-prefix=REJECT
; RUN: not llc -O2 -mtriple=x86_64-unknown-linux-gnu -mattr=+sahf %t/may-return.ll -o /dev/null 2>&1 | FileCheck %s --check-prefix=REJECT
;
; A noexcept handler may terminate if ending the catch throws. Its ordinary
; return is protected, but a similarly named helper without both guarantees
; must not be classified as a terminating branch.
; CHECK-LABEL: caught:
; CHECK: sahf
; CHECK: retq
; CHECK: callq __clang_call_terminate
; REJECT: in function caught {{.*}}X86 stack clearing does not support

;--- terminate.ll
declare i32 @__gxx_personality_v0(...)
declare void @may_throw()
declare void @__clang_call_terminate(ptr) noreturn nounwind

define i32 @caught(i32 %result) uwtable "zero-call-used-regs"="all" "zeroize-stack"="used" "zeroize-flags" personality ptr @__gxx_personality_v0 {
entry:
  invoke void @may_throw() to label %normal unwind label %terminate
normal:
  ret i32 %result
terminate:
  %exception = landingpad {ptr, i32} catch ptr null
  %object = extractvalue {ptr, i32} %exception, 0
  call void @__clang_call_terminate(ptr %object)
  unreachable
}

;--- may-unwind.ll
declare i32 @__gxx_personality_v0(...)
declare void @may_throw()
declare void @__clang_call_terminate(ptr) noreturn

define i32 @caught(i32 %result) uwtable "zero-call-used-regs"="all" "zeroize-stack"="used" "zeroize-flags" personality ptr @__gxx_personality_v0 {
entry:
  invoke void @may_throw() to label %normal unwind label %terminate
normal:
  ret i32 %result
terminate:
  %exception = landingpad {ptr, i32} catch ptr null
  %object = extractvalue {ptr, i32} %exception, 0
  call void @__clang_call_terminate(ptr %object)
  unreachable
}

;--- may-return.ll
declare i32 @__gxx_personality_v0(...)
declare void @may_throw()
declare void @__clang_call_terminate(ptr) nounwind

define i32 @caught(i32 %result) uwtable "zero-call-used-regs"="all" "zeroize-stack"="used" "zeroize-flags" personality ptr @__gxx_personality_v0 {
entry:
  invoke void @may_throw() to label %normal unwind label %terminate
normal:
  ret i32 %result
terminate:
  %exception = landingpad {ptr, i32} catch ptr null
  %object = extractvalue {ptr, i32} %exception, 0
  call void @__clang_call_terminate(ptr %object)
  unreachable
}
