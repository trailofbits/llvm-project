; The MMX registers are the significands of the x87 register file, so the x87
; stack clear zeroes them: MMn is physical x87 register n, fldz writes all 80
; bits, and fstp only pops. An MMX request is a request for that sequence. A
; function that wrote an MMX register leaves every x87 slot marked valid, so
; the stack is emptied first, and only then.

; RUN: split-file %s %t
; RUN: llc < %t/mmx.ll -mtriple=x86_64-unknown-linux-gnu -mattr=+mmx,+sse2 -verify-machineinstrs | FileCheck %s
; RUN: llc < %t/mmx.ll -mtriple=i386-unknown-linux-gnu -mattr=+mmx,+sse2 -verify-machineinstrs | FileCheck %s
; RUN: llc < %t/mmx.ll -mtriple=x86_64-unknown-linux-gnu -mattr=+mmx,+sse2 -verify-machineinstrs -o /dev/null 2>&1 | count 0

; Without MMX the registers are reserved: nothing is requested, nothing is
; reported, and the x87 clear is the x87 clear.
; RUN: llc < %t/int.ll -mtriple=x86_64-unknown-linux-gnu -mattr=-mmx -verify-machineinstrs | FileCheck --check-prefix=NOMMX %s
; RUN: llc < %t/int.ll -mtriple=x86_64-unknown-linux-gnu -mattr=-mmx -verify-machineinstrs -o /dev/null 2>&1 | count 0

; With MMX but without x87 the registers can be written and nothing can clear
; them, which is reported rather than skipped.
; RUN: not llc < %t/int.ll -mtriple=x86_64-unknown-linux-gnu -mattr=+mmx,-x87 -verify-machineinstrs -o /dev/null 2>&1 | FileCheck --check-prefix=NOX87 %s

;--- mmx.ll
; The function wrote %mm0, so the stack is emptied before it is filled.
define void @used_mmx(ptr %p, ptr %q) "zero-call-used-regs"="used" {
; CHECK-LABEL: used_mmx:
; CHECK:         paddd
; CHECK:         emms
; CHECK-COUNT-8: fldz
; CHECK-COUNT-8: fstp %st(0)
; CHECK-NOT:     fldz
; CHECK:         ret
  %a = load <1 x i64>, ptr %p
  %b = load <1 x i64>, ptr %q
  %r = call <1 x i64> @llvm.x86.mmx.padd.d(<1 x i64> %a, <1 x i64> %b)
  store <1 x i64> %r, ptr %p
  ret void
}

; "all" requests the MMX registers whether or not the function used them; a
; function that did not has an empty stack already.
define i32 @all_no_mmx_use(i32 %a) "zero-call-used-regs"="all" {
; CHECK-LABEL: all_no_mmx_use:
; CHECK-NOT:     emms
; CHECK-COUNT-8: fldz
; CHECK-COUNT-8: fstp %st(0)
; CHECK-NOT:     emms
; CHECK:         ret
  ret i32 %a
}

declare <1 x i64> @llvm.x86.mmx.padd.d(<1 x i64>, <1 x i64>)

;--- int.ll
define i32 @all_int(i32 %a) "zero-call-used-regs"="all" {
; NOMMX-LABEL: all_int:
; NOMMX-NOT:     emms
; NOMMX-COUNT-8: fldz
; NOMMX-COUNT-8: fstp %st(0)
; NOMMX-NOT:     emms
; NOMMX:         ret
  ret i32 %a
}

; NOX87: error: {{.*}}in function all_int{{.*}}clearing the call-used registers reached 'MM0, MM1, MM2, MM3, MM4, MM5, MM6, MM7', which this subtarget has no instruction to clear
