; RUN: not llc -O0 -mtriple=x86_64-unknown-linux-gnu -mattr=+sahf -verify-machineinstrs %s -o /dev/null 2>&1 | FileCheck %s
; RUN: not llc -O2 -mtriple=x86_64-unknown-linux-gnu -mattr=+sahf -verify-machineinstrs %s -o /dev/null 2>&1 | FileCheck %s
; CHECK: error: {{.*}}in function dynamic_frame {{.*}}X86 stack clearing does not support
; CHECK: error: {{.*}}in function realigned_frame {{.*}}X86 stack clearing does not support
; CHECK: error: {{.*}}in function has_handler {{.*}}X86 stack clearing does not support
; CHECK: error: {{.*}}in function exception_filter {{.*}}X86 stack clearing does not support
; CHECK: error: {{.*}}in function unknown_personality {{.*}}X86 stack clearing does not support
; CHECK: error: {{.*}}in function stack_only {{.*}}X86 stack clearing does not support
; CHECK: error: {{.*}}in function flags_only {{.*}}"zeroize-flags" is not supported

declare i32 @__gxx_personality_v0(...)
declare void @may_throw()
declare void @clean()
declare i32 @custom_personality(...)
declare void @use(ptr)

define i32 @dynamic_frame(i32 %result, i64 %size) "zero-call-used-regs"="all" "zeroize-stack"="used" "zeroize-flags" "frame-pointer"="all" personality ptr @__gxx_personality_v0 {
  %slot = alloca i8, i64 %size, align 8
  call void @use(ptr %slot)
  invoke void @may_throw() to label %normal unwind label %cleanup
normal:
  ret i32 %result
cleanup:
  %exception = landingpad {ptr, i32} cleanup
  call void @clean()
  resume {ptr, i32} %exception
}

define i32 @realigned_frame(i32 %result) "zero-call-used-regs"="all" "zeroize-stack"="used" "zeroize-flags" "frame-pointer"="all" personality ptr @__gxx_personality_v0 {
  %slot = alloca i64, align 64
  call void @use(ptr %slot)
  invoke void @may_throw() to label %normal unwind label %cleanup
normal:
  ret i32 %result
cleanup:
  %exception = landingpad {ptr, i32} cleanup
  call void @clean()
  resume {ptr, i32} %exception
}

define i32 @has_handler(i32 %result) "zero-call-used-regs"="all" "zeroize-stack"="used" "zeroize-flags" personality ptr @__gxx_personality_v0 {
  %slot = alloca i32, align 4
  store volatile i32 42, ptr %slot
  invoke void @may_throw() to label %normal unwind label %cleanup
normal:
  ret i32 %result
cleanup:
  %exception = landingpad {ptr, i32} catch ptr null
  call void @clean()
  resume {ptr, i32} %exception
}

define i32 @exception_filter() "zero-call-used-regs"="all" "zeroize-stack"="used" "zeroize-flags" personality ptr @__gxx_personality_v0 {
entry:
  invoke void @may_throw() to label %normal unwind label %cleanup
normal:
  ret i32 0
cleanup:
  %exception = landingpad {ptr, i32} cleanup filter [0 x ptr] zeroinitializer
  call void @clean()
  resume {ptr, i32} %exception
}

define i32 @unknown_personality(i32 %result) "zero-call-used-regs"="all" "zeroize-stack"="used" "zeroize-flags" personality ptr @custom_personality {
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

define i32 @stack_only(i32 %result) "zero-call-used-regs"="all" "zeroize-stack"="used" personality ptr @__gxx_personality_v0 {
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

define i32 @flags_only(i32 %result) "zeroize-flags" personality ptr @__gxx_personality_v0 {
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
