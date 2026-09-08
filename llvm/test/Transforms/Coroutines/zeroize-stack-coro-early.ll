; RUN: llvm-extract -S --func=protected_async --func=async_dispatch \
; RUN:   --func=must_tail_call_return --func=resume_context_projection \
; RUN:   --glob=protected_async_fp %s -o - | \
; RUN:   not opt -passes='module(coro-early),cgscc(coro-split)' \
; RUN:   -disable-output 2>&1 | FileCheck %s --check-prefix=ASYNC
; RUN: llvm-extract -S --func=protected_retcon %s -o - | \
; RUN:   not opt -passes='module(coro-early),cgscc(coro-split)' \
; RUN:   -disable-output 2>&1 | FileCheck %s --check-prefix=RETCON
; RUN: llvm-extract -S --func=protected_retcon_once %s -o - | \
; RUN:   not opt -passes='module(coro-early),cgscc(coro-split)' \
; RUN:   -disable-output 2>&1 | FileCheck %s --check-prefix=RETCON-ONCE

; ASYNC: error: cannot use the "zeroize-stack" attribute on a coroutine
; ASYNC-NOT: Broken module
; RETCON: error: cannot use the "zeroize-stack" attribute on a coroutine
; RETCON-NOT: Broken module
; RETCON-ONCE: error: cannot use the "zeroize-stack" attribute on a coroutine
; RETCON-ONCE-NOT: Broken module

%async_context = type { ptr, ptr }

@protected_async_fp = constant <{ i32, i32 }> <{ i32 0, i32 128 }>
@async_callee_fp = external global <{ i32, i32 }>

define swiftcc void @async_dispatch(ptr %callee, ptr %context, ptr %task,
                                    ptr %actor) {
  tail call swiftcc void %callee(ptr %context, ptr %task, ptr %actor)
  ret void
}

define swiftcc void @must_tail_call_return(ptr %context, ptr %task, ptr %actor) {
  musttail call swiftcc void @async_return(ptr %context, ptr %task, ptr %actor)
  ret void
}

define ptr @resume_context_projection(ptr %context) {
  %resume_context = load ptr, ptr %context
  ret ptr %resume_context
}

define swiftcc void @protected_async(ptr %context, ptr %task, ptr %actor)
    "zeroize-stack"="used" {
entry:
  %id = call token @llvm.coro.id.async(
      i32 128, i32 16, i32 0, ptr @protected_async_fp)
  %handle = call ptr @llvm.coro.begin(token %id, ptr null)
  %callee_context = call ptr @llvm.coro.async.context.alloc(
      ptr %task, ptr @async_callee_fp)
  %return_address = getelementptr inbounds %async_context, ptr %callee_context,
      i32 0, i32 1
  %resume = call ptr @llvm.coro.async.resume()
  store ptr %resume, ptr %return_address
  store ptr %context, ptr %callee_context
  %result = call { ptr, ptr, ptr } (i32, ptr, ptr, ...)
      @llvm.coro.suspend.async(i32 0, ptr %resume,
                              ptr @resume_context_projection,
                              ptr @async_dispatch, ptr @async_suspend,
                              ptr %callee_context, ptr %task, ptr %actor)
  %continuation_task = extractvalue { ptr, ptr, ptr } %result, 1
  call void (ptr, i1, ...) @llvm.coro.end.async(
      ptr %handle, i1 false, ptr @must_tail_call_return, ptr %context,
      ptr %continuation_task, ptr %actor)
  unreachable
}

define ptr @protected_retcon(ptr %storage) "zeroize-stack"="used" {
entry:
  %id = call token @llvm.coro.id.retcon(
      i32 8, i32 8, ptr %storage, ptr @prototype_retcon, ptr @allocate,
      ptr @deallocate)
  %handle = call ptr @llvm.coro.begin(token %id, ptr null)
  br label %loop

loop:
  %unwind = call i1 (...) @llvm.coro.suspend.retcon.i1()
  br i1 %unwind, label %cleanup, label %loop

cleanup:
  call void @llvm.coro.end(ptr %handle, i1 false, token none)
  unreachable
}

define ptr @protected_retcon_once(ptr %storage) "zeroize-stack"="used" {
entry:
  %id = call token @llvm.coro.id.retcon.once(
      i32 8, i32 8, ptr %storage, ptr @prototype_retcon_once, ptr @allocate,
      ptr @deallocate)
  ret ptr null
}

declare token @llvm.coro.id.async(i32, i32, i32, ptr)
declare token @llvm.coro.id.retcon(i32, i32, ptr, ptr, ptr, ptr)
declare token @llvm.coro.id.retcon.once(i32, i32, ptr, ptr, ptr, ptr)
declare ptr @llvm.coro.begin(token, ptr)
declare void @llvm.coro.end(ptr, i1, token)
declare void @llvm.coro.end.async(ptr, i1, ...)
declare i1 @llvm.coro.suspend.retcon.i1(...)
declare { ptr, ptr, ptr } @llvm.coro.suspend.async(i32, ptr, ptr, ...)
declare ptr @llvm.coro.async.context.alloc(ptr, ptr)
declare ptr @llvm.coro.async.resume()
declare swiftcc void @async_return(ptr, ptr, ptr)
declare swiftcc void @async_suspend(ptr, ptr, ptr)
declare ptr @prototype_retcon(ptr, i1 zeroext)
declare void @prototype_retcon_once(ptr, i1 zeroext)
declare noalias ptr @allocate(i32)
declare void @deallocate(ptr)
