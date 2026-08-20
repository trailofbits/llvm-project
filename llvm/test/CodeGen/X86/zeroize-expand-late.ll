; The clear survives because it is not a store until the very end. Both
; selectors emit an opaque pseudo with no memory operand, it is still that
; pseudo after the whole machine pipeline, and only
; X86AsmPrinter::emitInstruction turns it into a write. Pin those three points.
; MachineOutliner in particular is covered by zeroize-lowering.ll.

; RUN: llc -mtriple=x86_64-unknown-linux-gnu -verify-machineinstrs \
; RUN:   -stop-after=finalize-isel < %s | FileCheck %s --check-prefix=SELECTED
; RUN: llc -mtriple=x86_64-unknown-linux-gnu -verify-machineinstrs -global-isel \
; RUN:   -global-isel-abort=1 -stop-after=instruction-select < %s \
; RUN:   | FileCheck %s --check-prefix=SELECTED
; RUN: llc -mtriple=x86_64-unknown-linux-gnu -verify-machineinstrs \
; RUN:   -stop-before=x86-asm-printer < %s | FileCheck %s --check-prefix=PREEXPAND
; RUN: llc -mtriple=x86_64-unknown-linux-gnu -verify-machineinstrs -global-isel \
; RUN:   -global-isel-abort=1 -stop-before=x86-asm-printer < %s \
; RUN:   | FileCheck %s --check-prefix=PREEXPAND
; RUN: llc -mtriple=x86_64-unknown-linux-gnu -verify-machineinstrs < %s \
; RUN:   | FileCheck %s --check-prefix=EXPANDED
; RUN: llc -mtriple=x86_64-unknown-linux-gnu -verify-machineinstrs -global-isel \
; RUN:   -global-isel-abort=1 < %s | FileCheck %s --check-prefix=EXPANDED

declare void @llvm.zeroize.p0.i64(ptr nocapture writeonly, i64)

;; Both selectors hand the clear to the rest of the backend as one pseudo. It
;; carries no memory operand, so nothing downstream has a store to reason about;
;; the end-of-line anchor below is what pins that. The intrinsic node does get
;; one, so that lowering can read the destination address space back off it, but
;; that node is replaced here and the operand does not come with it.
; SELECTED-LABEL: name: zeroize
; SELECTED:         $rcx = COPY
; SELECTED-NEXT:    $rdi = COPY
; SELECTED-NEXT:    ZEROIZE64 implicit-def{{.*}} $eax, implicit-def{{.*}} $rcx, implicit-def{{.*}} $rdi, implicit $rcx, implicit $rdi{{$}}
; SELECTED-NOT:     MOV
; SELECTED-NOT:     STOS

;; Register allocation is over, every pass that could have removed or relocated
;; a store has run, and it is still the pseudo.
; PREEXPAND-LABEL: name: zeroize
; PREEXPAND:         ZEROIZE64
; PREEXPAND-NOT:     MOV32ri
; PREEXPAND-NOT:     STOS

;; Only in the emitted instructions does the write exist.
; EXPANDED-LABEL: zeroize:
; EXPANDED:         movl $0, %eax
; EXPANDED-NEXT:    rep;stosb %al, %es:(%rdi)

define void @zeroize(ptr %p, i64 %n) {
  call void @llvm.zeroize.p0.i64(ptr %p, i64 %n)
  ret void
}
