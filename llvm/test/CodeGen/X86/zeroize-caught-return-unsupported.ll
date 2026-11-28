; RUN: not llc -O0 -mtriple=x86_64-unknown-linux-gnu -mattr=+sahf -verify-machineinstrs %s -o /dev/null 2>&1 | FileCheck %s
; RUN: not llc -O2 -mtriple=x86_64-unknown-linux-gnu -mattr=+sahf -verify-machineinstrs %s -o /dev/null 2>&1 | FileCheck %s
;
; A catch plus a distinct outgoing cleanup is not an ordinary caught return.
; Unknown terminal calls must not be mistaken for Clang's terminate helper.
; CHECK: in function mixed_catch_resume {{.*}}X86 stack clearing does not support
; CHECK: in function unknown_named {{.*}}X86 stack clearing does not support
; CHECK: in function unknown_indirect {{.*}}X86 stack clearing does not support
; CHECK: in function unknown_personality {{.*}}X86 stack clearing does not support

declare i32 @__gxx_personality_v0(...)
declare i32 @custom_personality(...)
declare void @may_throw()
declare ptr @__cxa_begin_catch(ptr) nounwind
declare void @handler_may_throw()
declare void @__cxa_end_catch()
declare void @unknown_terminal() noreturn nounwind

define i32 @mixed_catch_resume(i32 %result) #0 personality ptr @__gxx_personality_v0 {
entry:
  invoke void @may_throw() to label %normal unwind label %catch
normal:
  ret i32 %result
catch:
  %exception = landingpad {ptr, i32} catch ptr null
  %object = extractvalue {ptr, i32} %exception, 0
  %caught = call ptr @__cxa_begin_catch(ptr %object)
  invoke void @handler_may_throw() to label %handled unwind label %outer_cleanup
handled:
  call void @__cxa_end_catch()
  ret i32 37
outer_cleanup:
  %outer_exception = landingpad {ptr, i32} cleanup
  call void @__cxa_end_catch()
  resume {ptr, i32} %outer_exception
}

define i32 @unknown_named(i32 %result) #0 personality ptr @__gxx_personality_v0 {
entry:
  invoke void @may_throw() to label %normal unwind label %catch
normal:
  ret i32 %result
catch:
  %exception = landingpad {ptr, i32} catch ptr null
  call void @unknown_terminal()
  unreachable
}

define i32 @unknown_indirect(ptr %target, i32 %result) #0 personality ptr @__gxx_personality_v0 {
entry:
  invoke void @may_throw() to label %normal unwind label %catch
normal:
  ret i32 %result
catch:
  %exception = landingpad {ptr, i32} catch ptr null
  notail call void %target() noreturn nounwind
  unreachable
}

define i32 @unknown_personality(i32 %result) #0 personality ptr @custom_personality {
entry:
  invoke void @may_throw() to label %normal unwind label %catch
normal:
  ret i32 %result
catch:
  %exception = landingpad {ptr, i32} catch ptr null
  ret i32 37
}

attributes #0 = { uwtable "zero-call-used-regs"="all" "zeroize-stack"="used" "zeroize-flags" }
