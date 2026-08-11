; What keeps the clear llvm.zeroize asks for from being optimized away is that
; it is not a store until the very end. Both selectors emit an opaque pseudo
; with no memory operand, and it is still that pseudo after register
; allocation; only X86ExpandPseudo, in addPreSched2, turns it into a write.
; Pin each of those three points.

; RUN: llc -mtriple=x86_64-unknown-linux-gnu -stop-after=finalize-isel < %s \
; RUN:   | FileCheck %s --check-prefix=SELECTED
; RUN: llc -mtriple=x86_64-unknown-linux-gnu -global-isel -global-isel-abort=1 \
; RUN:   -stop-after=instruction-select < %s | FileCheck %s --check-prefix=SELECTED
; RUN: llc -mtriple=x86_64-unknown-linux-gnu -stop-before=x86-expand-pseudo < %s \
; RUN:   | FileCheck %s --check-prefix=PREEXPAND
; RUN: llc -mtriple=x86_64-unknown-linux-gnu -global-isel -global-isel-abort=1 \
; RUN:   -stop-before=x86-expand-pseudo < %s | FileCheck %s --check-prefix=PREEXPAND
; RUN: llc -mtriple=x86_64-unknown-linux-gnu -stop-after=x86-expand-pseudo < %s \
; RUN:   | FileCheck %s --check-prefix=EXPANDED
; RUN: llc -mtriple=x86_64-unknown-linux-gnu -global-isel -global-isel-abort=1 \
; RUN:   -stop-after=x86-expand-pseudo < %s | FileCheck %s --check-prefix=EXPANDED

declare void @llvm.zeroize.p0.i64(ptr nocapture writeonly, i64)

;; Both selectors hand the clear to the rest of the backend as one pseudo. It
;; carries no memory operand, so nothing downstream has a store to reason about.
; SELECTED-LABEL: name: zeroize
; SELECTED:         $rcx = COPY
; SELECTED-NEXT:    $rdi = COPY
; SELECTED-NEXT:    ZEROIZE64 implicit-def{{.*}} $al, implicit-def{{.*}} $rcx, implicit-def{{.*}} $rdi, implicit $rcx, implicit $rdi
; SELECTED-NOT:     MOV
; SELECTED-NOT:     STOS

;; Register allocation is over and it is still the pseudo.
; PREEXPAND-LABEL: name: zeroize
; PREEXPAND:         ZEROIZE64
; PREEXPAND-NOT:     STOS

;; Only now does the write exist.
; EXPANDED-LABEL: name: zeroize
; EXPANDED-NOT:     ZEROIZE64
; EXPANDED:         $al = MOV8ri 0
; EXPANDED-NEXT:    REP_STOSB_64 implicit-def $rcx, implicit-def $rdi, implicit $al, implicit $rcx, implicit $rdi

define void @zeroize(ptr %p, i64 %n) {
  call void @llvm.zeroize.p0.i64(ptr %p, i64 %n)
  ret void
}
