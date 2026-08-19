; llvm.zeroize has to come back from bitcode covering the same region, in the
; same address space. A call that reloaded with a different length type or a
; different address space would clear something other than what was asked for,
; so check the reloaded calls rather than only that the module reloads. The
; second trip pins the first as a fixed point.
;
; The declarations carry the intrinsic's own properties. Those are restored from
; the intrinsic definition on load rather than read out of the bitcode, so
; checking them here says that the reloaded name still resolves to llvm.zeroize
; with a signature the definition accepts: a declaration that did not would come
; back as an ordinary function, with nothing left to keep the write alive.

; RUN: llvm-as < %s | llvm-dis > %t.ll
; RUN: FileCheck %s < %t.ll
; RUN: llvm-as < %t.ll | llvm-dis > %t2.ll
; RUN: diff %t.ll %t2.ll

; CHECK: declare void @llvm.zeroize.p0.i64(ptr writeonly captures(none), i64) #[[ATTRS:[0-9]+]]
; CHECK: declare void @llvm.zeroize.p0.i32(ptr writeonly captures(none), i32) #[[ATTRS]]
; CHECK: declare void @llvm.zeroize.p1.i64(ptr addrspace(1) writeonly captures(none), i64) #[[ATTRS]]
declare void @llvm.zeroize.p0.i64(ptr, i64)
declare void @llvm.zeroize.p0.i32(ptr, i32)
declare void @llvm.zeroize.p1.i64(ptr addrspace(1), i64)

; CHECK-LABEL: define void @clear(
; CHECK-NEXT: call void @llvm.zeroize.p0.i64(ptr align 16 %p, i64 %n64)
; CHECK-NEXT: call void @llvm.zeroize.p0.i32(ptr %p, i32 %n32)
; CHECK-NEXT: call void @llvm.zeroize.p1.i64(ptr addrspace(1) %q, i64 %n64)
; CHECK-NEXT: call void @llvm.zeroize.p0.i64(ptr %p, i64 16)
; CHECK-NEXT: ret void
define void @clear(ptr %p, ptr addrspace(1) %q, i32 %n32, i64 %n64) {
  call void @llvm.zeroize.p0.i64(ptr align 16 %p, i64 %n64)
  call void @llvm.zeroize.p0.i32(ptr %p, i32 %n32)
  call void @llvm.zeroize.p1.i64(ptr addrspace(1) %q, i64 %n64)
  call void @llvm.zeroize.p0.i64(ptr %p, i64 16)
  ret void
}

; CHECK: attributes #[[ATTRS]] = { nocallback nofree nosync nounwind willreturn memory(argmem: write, inaccessiblemem: write) }
