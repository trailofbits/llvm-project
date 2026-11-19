; RUN: llc -O0 -mtriple=x86_64-unknown-linux-gnu -mattr=+sahf -verify-machineinstrs %s -o - | FileCheck %s --check-prefixes=CHECK,O0
; RUN: llc -O2 -mtriple=x86_64-unknown-linux-gnu -mattr=+sahf -verify-machineinstrs %s -o - | FileCheck %s
; RUN: llc -O2 -mtriple=x86_64-unknown-linux-gnu -mattr=+sahf -frame-pointer=all -verify-machineinstrs %s -o - | FileCheck %s --check-prefix=FP
;
; A catch-all handler can return through the ordinary epilogue. End-catch is
; deliberately not nounwind: only a normal return that is reached is covered.
; Stack and flags requests remain independent for this ordinary exit.
;
; CHECK-LABEL: caught:
; CHECK: movq $0, {{.*}}(%rsp)
; CHECK: .cfi_def_cfa %rsp, 8
; CHECK: xchgq %r11, %rax
; CHECK-NEXT: testl %eax, %eax
; CHECK-NEXT: sahf
; CHECK-NEXT: xchgq %r11, %rax
; CHECK-NEXT: retq
; O0: movq $0, {{.*}}(%rsp)
; O0: .cfi_def_cfa %rsp, 8
; O0: xchgq %r11, %rax
; O0-NEXT: testl %eax, %eax
; O0-NEXT: sahf
; O0-NEXT: xchgq %r11, %rax
; O0-NEXT: retq
; CHECK-LABEL: caught_stack_only:
; CHECK: movq $0, {{.*}}(%rsp)
; CHECK: .cfi_def_cfa %rsp, 8
; CHECK: retq
; O0: movq $0, {{.*}}(%rsp)
; O0: .cfi_def_cfa %rsp, 8
; O0: retq
; CHECK-LABEL: caught_flags_only:
; CHECK: xchgq %r11, %rax
; CHECK-NEXT: testl %eax, %eax
; CHECK-NEXT: sahf
; CHECK-NEXT: xchgq %r11, %rax
; CHECK-NEXT: retq
; O0: xchgq %r11, %rax
; O0-NEXT: testl %eax, %eax
; O0-NEXT: sahf
; O0-NEXT: xchgq %r11, %rax
; O0-NEXT: retq
;
; FP-LABEL: caught:
; FP: .cfi_def_cfa_register %rbp
; FP: movq {{[0-9]+}}(%rsp), %rbp
; FP-NEXT: .cfi_restore %rbp
; FP-NEXT: movq $0, (%rsp)
; FP: .cfi_def_cfa %rsp, 8
; FP: sahf
; FP: retq

declare i32 @__gxx_personality_v0(...)
declare void @may_throw()
declare ptr @__cxa_begin_catch(ptr) nounwind
declare void @handler() nounwind
declare void @__cxa_end_catch()

define i32 @caught(i32 %result) uwtable "zero-call-used-regs"="all" "zeroize-stack"="used" "zeroize-flags" personality ptr @__gxx_personality_v0 {
entry:
  %slot = alloca i32, align 4
  store volatile i32 42, ptr %slot
  invoke void @may_throw() to label %normal unwind label %catch
normal:
  ret i32 %result
catch:
  %exception = landingpad {ptr, i32} catch ptr null
  %object = extractvalue {ptr, i32} %exception, 0
  %caught = call ptr @__cxa_begin_catch(ptr %object)
  call void @handler()
  call void @__cxa_end_catch()
  ret i32 37
}

define i32 @caught_stack_only(i32 %result) uwtable "zeroize-stack"="used" personality ptr @__gxx_personality_v0 {
entry:
  %slot = alloca i32, align 4
  store volatile i32 42, ptr %slot
  invoke void @may_throw() to label %normal unwind label %catch
normal:
  ret i32 %result
catch:
  %exception = landingpad {ptr, i32} catch ptr null
  %object = extractvalue {ptr, i32} %exception, 0
  %caught = call ptr @__cxa_begin_catch(ptr %object)
  call void @handler()
  call void @__cxa_end_catch()
  ret i32 37
}

define i32 @caught_flags_only(i32 %result) uwtable "zeroize-flags" personality ptr @__gxx_personality_v0 {
entry:
  %slot = alloca i32, align 4
  store volatile i32 42, ptr %slot
  invoke void @may_throw() to label %normal unwind label %catch
normal:
  ret i32 %result
catch:
  %exception = landingpad {ptr, i32} catch ptr null
  %object = extractvalue {ptr, i32} %exception, 0
  %caught = call ptr @__cxa_begin_catch(ptr %object)
  call void @handler()
  call void @__cxa_end_catch()
  ret i32 37
}
