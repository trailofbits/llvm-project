; A funclet leaves through a return out of an exception scope. That is a
; return-shaped exit, so it was already reached by the walk over return blocks
; that register clearing used to do, and it has to keep being reached now that
; the sequence is driven by the exit classification instead.

; RUN: llc -mtriple=x86_64-pc-windows-msvc -pei-print-clearing-sequence %s -o - 2>%t.seq | FileCheck %s
; RUN: FileCheck --check-prefix=SEQ %s < %t.seq

declare void @sink()
declare i32 @__CxxFrameHandler3(...)

; SEQ-LABEL: clearing sequence for function 'cleanup_funclet':
; SEQ-NEXT:  %bb.1 return: clear-stack=not-requested clear-registers=emitted clear-flags=unimplemented
; SEQ-NEXT:  %bb.2 eh-scope-return: clear-stack=not-requested clear-registers=emitted clear-flags=unimplemented
; SEQ-NEXT:  end clearing sequence for function 'cleanup_funclet'
;
; CHECK-LABEL: cleanup_funclet:
; CHECK:       xorl %edx, %edx
; CHECK-NEXT:  retq
; The cleanup funclet is a separate function in the object file, and it is
; cleared before it returns to the unwinder.
; CHECK-LABEL: "?dtor$2@?0?cleanup_funclet@4HA":
; CHECK:       xorl %edx, %edx
; CHECK-NEXT:  retq # CLEANUPRET
define void @cleanup_funclet() "zero-call-used-regs"="used-gpr" personality ptr @__CxxFrameHandler3 {
entry:
  invoke void @sink() to label %cont unwind label %pad

cont:
  ret void

pad:
  %cp = cleanuppad within none []
  call void @sink() [ "funclet"(token %cp) ]
  cleanupret from %cp unwind to caller
}
