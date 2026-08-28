; catchret carries isReturn, so it looks like an exit, but it leaves only the
; exception scope: the block it leaves from has a successor and the function
; continues there. The funclet ABI also returns the resumption address in %rax,
; which the personality reads out of the returning handler, so a clearing
; sequence in front of the catchret hands the personality a null address. Both
; reasons make the block not an exit; the return downstream of it is.

; RUN: llc -mtriple=x86_64-pc-windows-msvc -pei-print-clearing-sequence %s -o - 2>%t.seq | FileCheck %s
; RUN: FileCheck --check-prefix=SEQ %s < %t.seq

declare void @may_throw()
declare i32 @__CxxFrameHandler3(...)

; Only the return is in scope. The catch funclet's catchret is not listed.
; SEQ-LABEL: clearing sequence for function 'catch_and_return':
; SEQ-NEXT:  %bb.{{[0-9]+}} return: clear-stack=not-requested clear-registers=emitted clear-flags=unimplemented
; SEQ-NEXT:  end clearing sequence for function 'catch_and_return'

; CHECK-LABEL: catch_and_return:
;
; The catch funclet keeps the resumption address it loaded into %rax and clears
; nothing on its way out.
; CHECK-LABEL: "?catch$2@?0?catch_and_return@4HA":
; CHECK:         leaq .LBB{{[0-9]+}}_{{[0-9]+}}(%rip), %rax
; CHECK-NOT:     xorl %eax, %eax
; CHECK:         retq
define void @catch_and_return() "zero-call-used-regs"="used-gpr" personality ptr @__CxxFrameHandler3 {
entry:
  invoke void @may_throw() to label %join unwind label %cpad

cpad:
  %cs = catchswitch within none [label %handler] unwind to caller

handler:
  %cp = catchpad within %cs [ptr null, i32 64, ptr null]
  catchret from %cp to label %join

join:
  ret void
}
