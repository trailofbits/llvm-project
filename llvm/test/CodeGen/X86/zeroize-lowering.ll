; What the X86 lowering of llvm.zeroize accepts and what it refuses.
;
; The intrinsic promises a sequence, not just the bytes: no external call and no
; call frame. Where that sequence cannot be formed there is nothing weaker to
; fall back on, so the answer is an error rather than a different clear. Each
; refusal below is a case where no encoding of the sequence exists, and each is
; checked on both selectors so that neither quietly does something else.
;
; The cases that do lower and the cases that are refused cannot share a run,
; because the error stops compilation, hence split-file.

; RUN: split-file %s %t

;; No clearing sequence exists off x86-64 LP64. The count is overloaded on any
;; integer width, so the usual i64 count is an operand the type legalizer must
;; expand on a 32-bit subtarget, and it has no rule for an intrinsic node: it
;; dies before any lowering hook runs. Hence -O0 as well, and both widths.
; RUN: not llc -mtriple=i386-unknown-linux-gnu < %t/subtarget.ll 2>&1 \
; RUN:   | FileCheck %s --check-prefix=SUBTARGET
; RUN: not llc -mtriple=i386-unknown-linux-gnu -O0 < %t/subtarget.ll 2>&1 \
; RUN:   | FileCheck %s --check-prefix=SUBTARGET
; RUN: not llc -mtriple=x86_64-unknown-linux-gnux32 < %t/subtarget.ll 2>&1 \
; RUN:   | FileCheck %s --check-prefix=SUBTARGET
; RUN: not llc -mtriple=x86_64-unknown-linux-gnux32 -global-isel \
; RUN:   -global-isel-abort=1 < %t/subtarget.ll 2>&1 \
; RUN:   | FileCheck %s --check-prefix=SUBTARGET

;; A string instruction writes ES:[RDI] and cannot override its destination
;; segment (Intel SDM, STOS: "The ES segment cannot be overridden with a
;; segment override prefix"), so no encoding reaches a GS, FS or SS region.
;; Clearing the flat address the offset names would erase unrelated memory and
;; leave the region intact, silently.
; RUN: not llc -mtriple=x86_64-unknown-linux-gnu < %t/segment.ll 2>&1 \
; RUN:   | FileCheck %s --check-prefix=SEGMENT
; RUN: not llc -mtriple=x86_64-unknown-linux-gnu -global-isel \
; RUN:   -global-isel-abort=1 < %t/segment.ll 2>&1 \
; RUN:   | FileCheck %s --check-prefix=SEGMENT

;; A PTR32 pointer is 32 bits wide and is not an address until widened.
;; GlobalISel models p0 only and cannot widen one, so both selectors refuse
;; rather than one supporting the space and the other falling back.
; RUN: not llc -mtriple=x86_64-unknown-linux-gnu < %t/ptr32.ll 2>&1 \
; RUN:   | FileCheck %s --check-prefix=PTR32
; RUN: not llc -mtriple=x86_64-unknown-linux-gnu -global-isel \
; RUN:   -global-isel-abort=1 < %t/ptr32.ll 2>&1 \
; RUN:   | FileCheck %s --check-prefix=PTR32

;; A count that cannot be shown to fit in %rcx is refused rather than
;; truncated: a wipe that quietly clears fewer bytes than asked is worse than
;; one that refuses.
; RUN: not llc -mtriple=x86_64-unknown-linux-gnu < %t/count.ll 2>&1 \
; RUN:   | FileCheck %s --check-prefix=COUNT
; RUN: not llc -mtriple=x86_64-unknown-linux-gnu -global-isel \
; RUN:   -global-isel-abort=1 < %t/count.ll 2>&1 \
; RUN:   | FileCheck %s --check-prefix=COUNT

;; Everything that does lower, on both selectors and at both -O0 and -O2.
; RUN: llc -mtriple=x86_64-unknown-linux-gnu -verify-machineinstrs \
; RUN:   < %t/lower.ll | FileCheck %s --check-prefix=LOWER
; RUN: llc -mtriple=x86_64-unknown-linux-gnu -global-isel -global-isel-abort=1 \
; RUN:   -verify-machineinstrs < %t/lower.ll | FileCheck %s --check-prefix=LOWER
; RUN: llc -O0 -mtriple=x86_64-unknown-linux-gnu -verify-machineinstrs \
; RUN:   < %t/lower.ll | FileCheck %s --check-prefix=LOWER
; RUN: llc -O0 -mtriple=x86_64-unknown-linux-gnu -global-isel \
; RUN:   -global-isel-abort=1 -verify-machineinstrs < %t/lower.ll \
; RUN:   | FileCheck %s --check-prefix=LOWER

;; MachineOutliner takes the no-call-frame half away without removing anything:
;; it lifts a repeated run into a function and leaves a call behind. The clear
;; stays an opaque pseudo until emission, past the outliner, and
;; X86InstrInfo::getOutliningTypeImpl refuses it.
; RUN: llc -mtriple=x86_64-unknown-linux-gnu -enable-machine-outliner \
; RUN:   -verify-machineinstrs < %t/outliner.ll \
; RUN:   | FileCheck %s --check-prefix=OUTLINE

;; What address space 256 is supposed to mean, as the reference for why the
;; clear cannot reach it. SelectionDAG only: GlobalISel cannot legalize a store
;; through a non-p0 pointer, which is unrelated to llvm.zeroize.
; RUN: llc -mtriple=x86_64-unknown-linux-gnu -verify-machineinstrs \
; RUN:   < %t/segment-reference.ll | FileCheck %s --check-prefix=SEGREF

; SUBTARGET: error: {{.*}}llvm.zeroize has no clearing sequence on this subtarget
; SUBTARGET-NOT: PLEASE submit a bug report
; SUBTARGET-NOT: Cannot select
; SUBTARGET-NOT: Do not know how to expand

; SEGMENT: error: {{.*}}llvm.zeroize cannot clear a segment-relative region
; SEGMENT-NOT: PLEASE submit a bug report

; PTR32: error: {{.*}}llvm.zeroize cannot clear a region whose pointer is not a 64-bit address
; PTR32-NOT: PLEASE submit a bug report
; PTR32-NOT: Cannot emit physreg copy

; COUNT: error: {{.*}}llvm.zeroize cannot clear a region whose length does not fit in 64 bits
; COUNT-NOT: PLEASE submit a bug report
; COUNT-NOT: Do not know how to expand

;; Address spaces 0, 1 and 272 are flat 64-bit pointers and need no adjustment.
; LOWER-LABEL: flat:
; LOWER:         rep;stosb
; LOWER-LABEL: user_defined:
; LOWER:         rep;stosb
; LOWER-LABEL: ptr64:
; LOWER:         rep;stosb

;; A count wider than 64 bits whose value provably fits asks for nothing more,
;; so it is narrowed rather than refused. The narrowing happens before the type
;; legalizer, which has no rule for expanding a wide operand of an intrinsic.
; LOWER-LABEL: wide_count_that_fits:
; LOWER:         movl $32, %ecx
; LOWER:         rep;stosb

;; An ordinary store to address space 256 carries the segment override, which is
;; what makes the pointer a GS offset and what the clearing sequence cannot do.
; SEGREF-LABEL: store_gs:
; SEGREF:         movq $0, %gs:(%rdi)

;; Each clear keeps its own rep;stosb and none becomes a call. The run is long
;; enough to be worth outlining and does not reach the return, so without the
;; refusal the clear would land in OUTLINED_FUNCTION_0 reached by callq. The
;; same shape with a memset is still outlined, so the difference is what is
;; pinned rather than the outliner being off.
; OUTLINE-LABEL: zeroize_a:
; OUTLINE-NOT:     callq OUTLINED_FUNCTION
; OUTLINE:         rep;stosb
; OUTLINE-NOT:     callq OUTLINED_FUNCTION
; OUTLINE:         retq
; OUTLINE-LABEL: zeroize_b:
; OUTLINE-NOT:     callq OUTLINED_FUNCTION
; OUTLINE:         rep;stosb
; OUTLINE-NOT:     callq OUTLINED_FUNCTION
; OUTLINE:         retq
; OUTLINE-LABEL: memset_a:
; OUTLINE:         callq OUTLINED_FUNCTION

;--- subtarget.ll
declare void @llvm.zeroize.p0.i64(ptr nocapture writeonly, i64)
declare void @llvm.zeroize.p0.i32(ptr nocapture writeonly, i32)

define void @wide_count(ptr %p, i64 %n) {
  call void @llvm.zeroize.p0.i64(ptr %p, i64 %n)
  ret void
}

define void @narrow_count(ptr %p, i32 %n) {
  call void @llvm.zeroize.p0.i32(ptr %p, i32 %n)
  ret void
}

;--- segment.ll
declare void @llvm.zeroize.p256.i64(ptr addrspace(256), i64)

define void @zeroize_gs(ptr addrspace(256) %p) {
  call void @llvm.zeroize.p256.i64(ptr addrspace(256) %p, i64 16)
  ret void
}

;--- ptr32.ll
target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128"

declare void @llvm.zeroize.p270.i64(ptr addrspace(270), i64)

define void @zeroize_sptr(ptr addrspace(270) %p) {
  call void @llvm.zeroize.p270.i64(ptr addrspace(270) %p, i64 16)
  ret void
}

;--- count.ll
declare void @llvm.zeroize.p0.i128(ptr, i128)

;; 2^64, one past what %rcx can hold.
define void @constant_too_large(ptr %p) {
  call void @llvm.zeroize.p0.i128(ptr %p, i128 18446744073709551616)
  ret void
}

;; Not known, so nothing can be shown about it.
define void @unknown(ptr %p, i128 %n) {
  call void @llvm.zeroize.p0.i128(ptr %p, i128 %n)
  ret void
}

;--- lower.ll
target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128"

declare void @llvm.zeroize.p0.i64(ptr, i64)
declare void @llvm.zeroize.p1.i64(ptr addrspace(1), i64)
declare void @llvm.zeroize.p272.i64(ptr addrspace(272), i64)
declare void @llvm.zeroize.p0.i128(ptr, i128)

define void @flat(ptr %p) {
  call void @llvm.zeroize.p0.i64(ptr %p, i64 16)
  ret void
}

define void @user_defined(ptr addrspace(1) %p) {
  call void @llvm.zeroize.p1.i64(ptr addrspace(1) %p, i64 16)
  ret void
}

define void @ptr64(ptr addrspace(272) %p) {
  call void @llvm.zeroize.p272.i64(ptr addrspace(272) %p, i64 16)
  ret void
}

define void @wide_count_that_fits(ptr %p) {
  call void @llvm.zeroize.p0.i128(ptr %p, i128 32)
  ret void
}

;--- segment-reference.ll
define void @store_gs(ptr addrspace(256) %p) {
  store i64 0, ptr addrspace(256) %p
  ret void
}

;--- outliner.ll
declare void @llvm.zeroize.p0.i64(ptr nocapture writeonly, i64)
declare void @llvm.memset.p0.i64(ptr nocapture writeonly, i8, i64, i1)

define i64 @zeroize_a(ptr %p, i64 %n, ptr %q) minsize {
  store i64 11, ptr %q
  store i64 22, ptr %q
  store i64 33, ptr %q
  call void @llvm.zeroize.p0.i64(ptr %p, i64 %n)
  store i64 44, ptr %q
  ret i64 7
}

define i64 @zeroize_b(ptr %p, i64 %n, ptr %q) minsize {
  store i64 11, ptr %q
  store i64 22, ptr %q
  store i64 33, ptr %q
  call void @llvm.zeroize.p0.i64(ptr %p, i64 %n)
  store i64 44, ptr %q
  ret i64 9
}

define i64 @zeroize_c(ptr %p, i64 %n, ptr %q) minsize {
  store i64 11, ptr %q
  store i64 22, ptr %q
  store i64 33, ptr %q
  call void @llvm.zeroize.p0.i64(ptr %p, i64 %n)
  store i64 44, ptr %q
  ret i64 13
}

define i64 @memset_a(ptr %p, ptr %q) minsize {
  store i64 55, ptr %q
  store i64 66, ptr %q
  store i64 77, ptr %q
  call void @llvm.memset.p0.i64(ptr %p, i8 0, i64 64, i1 true)
  store i64 88, ptr %q
  ret i64 7
}

define i64 @memset_b(ptr %p, ptr %q) minsize {
  store i64 55, ptr %q
  store i64 66, ptr %q
  store i64 77, ptr %q
  call void @llvm.memset.p0.i64(ptr %p, i8 0, i64 64, i1 true)
  store i64 88, ptr %q
  ret i64 9
}

define i64 @memset_c(ptr %p, ptr %q) minsize {
  store i64 55, ptr %q
  store i64 66, ptr %q
  store i64 77, ptr %q
  call void @llvm.memset.p0.i64(ptr %p, i8 0, i64 64, i1 true)
  store i64 88, ptr %q
  ret i64 13
}
