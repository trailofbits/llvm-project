; RUN: opt -passes='module(coro-early),cgscc(coro-split),module(coro-cleanup)' \
; RUN:   -verify-each -S %s | FileCheck %s

; Continuations retain flags clearing from the original coroutine and the
; calling convention, parameter attributes, and function attributes of the ABI
; prototype. Unprotected coroutines do not acquire flags clearing.

@marker = global i32 0

; CHECK-LABEL: define ptr @protected_retcon(
; CHECK-LABEL: define internal fastcc ptr @protected_retcon.resume.0(
; CHECK-SAME: i1 zeroext
; CHECK-SAME: #[[PROTECTED:[0-9]+]]
define ptr @protected_retcon(ptr %storage) "zeroize-flags" {
entry:
  %id = call token @llvm.coro.id.retcon(
      i32 8, i32 8, ptr %storage, ptr @prototype_retcon, ptr @allocate, ptr @deallocate)
  %handle = call ptr @llvm.coro.begin(token %id, ptr null)
  br label %suspend

suspend:
  store volatile i32 42, ptr @marker
  %unwind = call i1 (...) @llvm.coro.suspend.retcon.i1()
  br i1 %unwind, label %cleanup, label %suspend

cleanup:
  call void @llvm.coro.end(ptr %handle, i1 false, token none)
  unreachable
}

; CHECK-LABEL: define ptr @plain_retcon(
; CHECK-LABEL: define internal fastcc ptr @plain_retcon.resume.0(
; CHECK-SAME: i1 zeroext
; CHECK-SAME: #[[PLAIN:[0-9]+]]
define ptr @plain_retcon(ptr %storage) {
entry:
  %id = call token @llvm.coro.id.retcon(
      i32 8, i32 8, ptr %storage, ptr @prototype_retcon, ptr @allocate, ptr @deallocate)
  %handle = call ptr @llvm.coro.begin(token %id, ptr null)
  br label %suspend

suspend:
  store volatile i32 42, ptr @marker
  %unwind = call i1 (...) @llvm.coro.suspend.retcon.i1()
  br i1 %unwind, label %cleanup, label %suspend

cleanup:
  call void @llvm.coro.end(ptr %handle, i1 false, token none)
  unreachable
}

; CHECK-LABEL: define ptr @protected_once(
; CHECK-LABEL: define internal fastcc void @protected_once.resume.0(
; CHECK-SAME: i1 zeroext
; CHECK-SAME: #[[PROTECTED]]
define ptr @protected_once(ptr %storage) "zeroize-flags" {
entry:
  %id = call token @llvm.coro.id.retcon.once(
      i32 8, i32 8, ptr %storage, ptr @prototype_once, ptr @allocate, ptr @deallocate)
  %handle = call ptr @llvm.coro.begin(token %id, ptr null)
  br label %suspend

suspend:
  store volatile i32 42, ptr @marker
  %unwind = call i1 (...) @llvm.coro.suspend.retcon.i1()
  br i1 %unwind, label %cleanup, label %resume

resume:
  store volatile i32 7, ptr @marker
  br label %cleanup

cleanup:
  call void @llvm.coro.end(ptr %handle, i1 false, token none)
  unreachable
}

; CHECK-LABEL: define ptr @plain_once(
; CHECK-LABEL: define internal fastcc void @plain_once.resume.0(
; CHECK-SAME: i1 zeroext
; CHECK-SAME: #[[PLAIN]]
define ptr @plain_once(ptr %storage) {
entry:
  %id = call token @llvm.coro.id.retcon.once(
      i32 8, i32 8, ptr %storage, ptr @prototype_once, ptr @allocate, ptr @deallocate)
  %handle = call ptr @llvm.coro.begin(token %id, ptr null)
  br label %suspend

suspend:
  store volatile i32 42, ptr @marker
  %unwind = call i1 (...) @llvm.coro.suspend.retcon.i1()
  br i1 %unwind, label %cleanup, label %resume

resume:
  store volatile i32 7, ptr @marker
  br label %cleanup

cleanup:
  call void @llvm.coro.end(ptr %handle, i1 false, token none)
  unreachable
}

; CHECK-DAG: attributes #[[PROTECTED]] = { noinline nounwind "zeroize-flags" }
; CHECK-DAG: attributes #[[PLAIN]] = { noinline nounwind }

declare token @llvm.coro.id.retcon(i32, i32, ptr, ptr, ptr, ptr)
declare token @llvm.coro.id.retcon.once(i32, i32, ptr, ptr, ptr, ptr)
declare ptr @llvm.coro.begin(token, ptr)
declare i1 @llvm.coro.suspend.retcon.i1(...)
declare void @llvm.coro.end(ptr, i1, token)
declare fastcc ptr @prototype_retcon(ptr, i1 zeroext) noinline nounwind
declare fastcc void @prototype_once(ptr, i1 zeroext) noinline nounwind
declare noalias ptr @allocate(i32)
declare void @deallocate(ptr)
