; RUN: llc -mtriple=aarch64-linux-gnu -mattr=+pauth -verify-machineinstrs -stop-before=prolog-epilog %s -o - | FileCheck %s --check-prefix=RA
; RUN: llc -mtriple=aarch64-linux-gnu -mattr=+pauth -verify-machineinstrs %s -o - | FileCheck %s --check-prefix=ASM

; The vector is live across an invoke. With no IR alloca, the 16-byte stack
; object must come from register allocation. The catch handles the exception
; locally and branches back to the same signed return as the ordinary path.
;
; RA-LABEL: name: signed_spill
; RA: id: [[SLOT:[0-9]+]], name: '', type: spill-slot, offset: {{-?[0-9]+}}, size: 16,
; RA: STRQui $q0, %stack.[[SLOT]], 0
; RA: BL @may_throw
; RA: bb.{{[0-9]+}}.caught (landing-pad):
; RA: BL @__cxa_end_catch
; RA: bb.{{[0-9]+}}.exit:
; RA: $q0 = LDRQui %stack.[[SLOT]], 0
; RA: BL @use
; RA: RET_ReallyLR implicit $w0
;
; ASM-LABEL: signed_spill:
; ASM: paciasp
; ASM: sub sp, sp, #32
; ASM: str q0, [sp]
; ASM: bl may_throw
; ASM: mov [[ADJUST:w[0-9]+]], #3
; ASM-NEXT: [[EXIT:\.LBB[0-9]+_[0-9]+]]:
; ASM-NEXT: ldr q0, [sp]
; ASM-NEXT: bl use
; ASM-NEXT: add w0, w0, [[ADJUST]]
; ASM: ldr x30,
; ASM: mov [[WIPE:x[0-9]+]], sp
; ASM-NEXT: stp xzr, xzr, {{\[}}[[WIPE]]]
; ASM-NEXT: stp xzr, xzr, {{\[}}[[WIPE]], #16]
; ASM-NEXT: add [[WIPE]], [[WIPE]], #32
; ASM-NEXT: mov sp, [[WIPE]]
; ASM: msr NZCV, xzr
; ASM-NEXT: retaa
; ASM: bl __cxa_begin_catch
; ASM: bl __cxa_end_catch
; ASM: mov [[ADJUST]], #7
; ASM-NEXT: b [[EXIT]]

declare i32 @__gxx_personality_v0(...)
declare ptr @__cxa_begin_catch(ptr)
declare void @__cxa_end_catch()
declare void @may_throw()
declare i32 @use(<2 x i64>) nounwind

define i32 @signed_spill(<2 x i64> %value) #0 personality ptr @__gxx_personality_v0 {
entry:
  invoke void @may_throw() to label %normal unwind label %caught

normal:
  br label %exit

caught:
  %lp = landingpad { ptr, i32 } catch ptr null
  %exception = extractvalue { ptr, i32 } %lp, 0
  call ptr @__cxa_begin_catch(ptr %exception)
  call void @__cxa_end_catch()
  br label %exit

exit:
  %adjust = phi i32 [ 3, %normal ], [ 7, %caught ]
  %result = call i32 @use(<2 x i64> %value)
  %sum = add i32 %result, %adjust
  ret i32 %sum
}

attributes #0 = { "sign-return-address"="non-leaf" "zeroize-stack"="used" "zero-call-used-regs"="all" "zeroize-flags" }
