; RUN: split-file %s %t
; RUN: cat %t/input.ll %t/projection-stack.ll > %t/projection.ll
; RUN: not opt -passes='module(coro-early),cgscc(coro-split)' -verify-each \
; RUN:   -disable-output %t/projection.ll 2>&1 | FileCheck %s --check-prefix=PROJECTION
; RUN: cat %t/input.ll %t/suspend-flags.ll > %t/suspend.ll
; RUN: not opt -passes='module(coro-early),cgscc(coro-split)' -verify-each \
; RUN:   -disable-output %t/suspend.ll 2>&1 | FileCheck %s --check-prefix=SUSPEND
; RUN: cat %t/input.ll %t/end-flags.ll > %t/end.ll
; RUN: not opt -passes='module(coro-early),cgscc(coro-split)' -verify-each \
; RUN:   -disable-output %t/end.ll 2>&1 | FileCheck %s --check-prefix=END
; RUN: cat %t/input.ll %t/compatible-flags.ll > %t/compatible.ll
; RUN: opt -passes='module(coro-early),cgscc(coro-split)' -verify-each \
; RUN:   -S %t/compatible.ll | FileCheck %s --check-prefix=COMPATIBLE

; PROJECTION: error: cannot inline async coroutine helper 'project':
; PROJECTION-SAME: incompatible zeroize-stack attributes
; SUSPEND: error: cannot inline async coroutine helper 'dispatch':
; SUSPEND-SAME: incompatible zeroize-flags attributes
; END: error: cannot inline async coroutine helper 'finish':
; END-SAME: incompatible zeroize-flags attributes
; COMPATIBLE-LABEL: define swifttailcc void @async(
; COMPATIBLE-SAME: #[[FLAGS:[0-9]+]]
; COMPATIBLE-NOT: @llvm.coro.suspend.async
; COMPATIBLE: musttail call swifttailcc void @callee(
; COMPATIBLE-LABEL: define internal swifttailcc void @async.resume.0(
; COMPATIBLE-SAME: #[[FLAGS]]
; COMPATIBLE-NOT: call ptr @project(
; COMPATIBLE: ret void
; COMPATIBLE: attributes #[[FLAGS]] = { "zeroize-flags" }

;--- input.ll
target datalayout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128"
target triple = "x86_64-unknown-linux-gnu"

@descriptor = global <{ i32, i32 }> <{ i32 0, i32 16 }>

define swifttailcc void @async(ptr swiftasync %ctx) #0 {
  %id = call token @llvm.coro.id.async(i32 16, i32 16, i32 0, ptr @descriptor)
  %frame = call ptr @llvm.coro.begin(token %id, ptr null)
  %resume = call ptr @llvm.coro.async.resume()
  %resume.slot = getelementptr ptr, ptr %ctx, i32 1
  store ptr %resume, ptr %resume.slot
  %result = call { ptr } (i32, ptr, ptr, ...) @llvm.coro.suspend.async.sl_p0s(
      i32 0, ptr %resume, ptr @project, ptr @dispatch, ptr @callee, ptr %ctx)
  %newctx = extractvalue { ptr } %result, 0
  call void (ptr, i1, ...) @llvm.coro.end.async(
      ptr %frame, i1 false, ptr @finish, ptr @callee, ptr %newctx)
  unreachable
}

define internal ptr @project(ptr %ctx) #1 {
  ret ptr %ctx
}

define internal swifttailcc void @dispatch(ptr %fn, ptr %ctx) #2 {
  musttail call swifttailcc void %fn(ptr swiftasync %ctx)
  ret void
}

define internal swifttailcc void @finish(ptr %fn, ptr %ctx) #3 {
  musttail call swifttailcc void %fn(ptr swiftasync %ctx)
  ret void
}

declare swifttailcc void @callee(ptr swiftasync)
declare token @llvm.coro.id.async(i32, i32, i32, ptr)
declare ptr @llvm.coro.begin(token, ptr)
declare ptr @llvm.coro.async.resume()
declare { ptr } @llvm.coro.suspend.async.sl_p0s(i32, ptr, ptr, ...)
declare void @llvm.coro.end.async(ptr, i1, ...)

;--- projection-stack.ll
attributes #0 = { nounwind }
attributes #1 = { "zeroize-stack"="used" }
attributes #2 = { nounwind }
attributes #3 = { nounwind }

;--- suspend-flags.ll
attributes #0 = { nounwind }
attributes #1 = { nounwind }
attributes #2 = { "zeroize-flags" }
attributes #3 = { nounwind }

;--- end-flags.ll
attributes #0 = { nounwind }
attributes #1 = { nounwind }
attributes #2 = { nounwind }
attributes #3 = { "zeroize-flags" }

;--- compatible-flags.ll
attributes #0 = { "zeroize-flags" }
attributes #1 = { "zeroize-flags" }
attributes #2 = { "zeroize-flags" }
attributes #3 = { "zeroize-flags" }
