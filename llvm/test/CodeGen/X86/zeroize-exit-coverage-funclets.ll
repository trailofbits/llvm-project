; The Windows personalities put cleanups and handlers in funclets, which leave
; through a return out of an exception scope rather than through a call back
; into the unwinder. Both are exits with the funclet's frame established, so
; both are in scope; emitting there is
; trailofbits/vspells-ct-internal-notes#25.

; RUN: llc -mtriple=x86_64-pc-windows-msvc -pei-print-exits %s -o /dev/null 2>&1 | FileCheck %s

declare void @sink()
declare i32 @__CxxFrameHandler3(...)

@typeinfo = external global ptr

; CHECK-LABEL: exits for function 'cleanup_funclet':
; CHECK-NEXT:  %bb.1: return [in-scope]
; CHECK-NEXT:  %bb.2: eh-scope-return [in-scope]
; CHECK-NEXT:  end exits for function 'cleanup_funclet'
define void @cleanup_funclet() personality ptr @__CxxFrameHandler3 {
entry:
  invoke void @sink() to label %cont unwind label %pad

cont:
  ret void

pad:
  %cp = cleanuppad within none []
  call void @sink() [ "funclet"(token %cp) ]
  cleanupret from %cp unwind to caller
}

; catchret names the block the parent resumes at, so unlike every other exit
; its block has a successor. It is still an exit: the funclet's frame is
; released by it.
; CHECK-LABEL: exits for function 'catch_funclet':
; CHECK-NEXT:  %bb.1: return [in-scope]
; CHECK-NEXT:  %bb.2: eh-scope-return [in-scope]
; CHECK-NEXT:  end exits for function 'catch_funclet'
define void @catch_funclet() personality ptr @__CxxFrameHandler3 {
entry:
  invoke void @sink() to label %cont unwind label %pad

cont:
  ret void

pad:
  %cs = catchswitch within none [label %handler] unwind to caller

handler:
  %cp = catchpad within %cs [ptr @typeinfo, i32 0, ptr null]
  catchret from %cp to label %cont
}
