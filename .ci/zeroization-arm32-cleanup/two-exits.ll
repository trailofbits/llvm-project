; SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
; Explicitly EH-lowered IR: this exercises two backend cleanup transfers, not
; frontend lowering. The runner disables tail merging and executes both inputs.
target triple = "armv7-linux-gnueabihf"
declare void @action(i32)
declare void @__cxa_end_cleanup()
declare void @event(i32) nounwind
declare i32 @__gxx_personality_v0(...)
define i32 @inner(i32 %value) #0 section "innercode" personality ptr @__gxx_personality_v0 {
entry:
  %words = alloca [6 x i32], align 4
  %slot = getelementptr [6 x i32], ptr %words, i32 0, i32 1
  store volatile i32 %value, ptr %slot
  call void asm sideeffect "movw r4, #0x5511\0Amovt r4,#0x7733", "r,~{r4},~{memory}"(ptr %words)
  %lowbit=and i32 %value, 1
  %odd=icmp ne i32 %lowbit,0
  br i1 %odd, label %oddcall,label %evencall
oddcall:
  invoke void @action(i32 1) to label %oddret unwind label %oddcleanup
evencall:
  invoke void @action(i32 2) to label %evenret unwind label %evencleanup
oddret:
  call void @event(i32 3)
  call void @event(i32 1)
  %a=load volatile i32,ptr %slot
  ret i32 %a
evenret:
  call void @event(i32 1)
  %b=load volatile i32,ptr %slot
  ret i32 %b
oddcleanup:
  %exn1=landingpad {ptr,i32} cleanup
  call void @event(i32 3)
  call void @event(i32 1)
  call arm_aapcs_vfpcc void @__cxa_end_cleanup() #1
  unreachable
evencleanup:
  %exn2=landingpad {ptr,i32} cleanup
  call void @event(i32 1)
  call arm_aapcs_vfpcc void @__cxa_end_cleanup() #1
  unreachable
}
attributes #0={ "zeroize-stack"="used" "zero-call-used-regs"="all-gpr" "zeroize-flags" "frame-pointer"="none" }

attributes #1={ noreturn nomerge }
