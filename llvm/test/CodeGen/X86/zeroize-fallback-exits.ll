; A block with no successors that ends in something the emission cannot account
; for used to be passed over, which is the claim that control stops there and
; nothing needs clearing. Not recognizing an instruction is not the same as
; knowing what it does, and the two answers are not symmetric: an opaque
; instruction that does leave the function takes the frame and the registers
; with it, while one that does not costs a dead sequence in a block nothing
; reaches. The uncertainty resolves towards clearing.
;
; trailofbits/vspells-ct-internal-notes#24.

; RUN: llc -mtriple=x86_64-unknown-linux-gnu -pei-print-clearing-sequence %s -o /dev/null 2>&1 | FileCheck --check-prefix=SEQ %s
; RUN: llc -mtriple=x86_64-unknown-linux-gnu %s -o - | FileCheck %s

@g = external global i64

declare void @llvm.trap()

; Inline assembly at the end of a block with no successors. It can jump, it can
; issue a system call that does not come back, and nothing here can tell.
; SEQ-LABEL: clearing sequence for function 'opaque_asm':
; SEQ-NEXT:  %bb.0 unknown: clear-stack=not-requested clear-registers=emitted clear-flags=unimplemented
; SEQ-NEXT:  end clearing sequence for function 'opaque_asm'
;
; The sequence goes in front of the asm, because after it is after the
; function. The registers the earlier computation used are cleared there; the
; ones the asm declares are left alone, the same as at any other exit, because
; an exit cannot be given a sequence that breaks the instruction it leaves
; through.
; CHECK-LABEL: opaque_asm:
; CHECK:       xorl %eax, %eax
; CHECK-NEXT:  xorl %edi, %edi
; CHECK-NEXT:  xorl %esi, %esi
; CHECK-NEXT:  #APP
; CHECK-NEXT:  hlt
define void @opaque_asm(i64 %a, i64 %b) "zero-call-used-regs"="used-gpr" {
  %s = add i64 %a, %b
  store i64 %s, ptr @g
  call void asm sideeffect "hlt", "~{memory}"()
  unreachable
}

; A trap is still out of scope, and this is what keeps the change from being a
; blanket "clear everywhere". The target has marked the instruction as a trap,
; so control stopping in the block is something known rather than something
; that could not be ruled out. The list is pinned between the two lines that
; bracket it, so an exit that started being emitted at would show up here.
; SEQ-LABEL: clearing sequence for function 'traps':
; SEQ-NEXT:  end clearing sequence for function 'traps'
;
; CHECK-LABEL: traps:
; CHECK-NOT:   xorl
; CHECK:       ud2
define void @traps(i64 %a, i64 %b) "zero-call-used-regs"="used-gpr" {
  %s = add i64 %a, %b
  store i64 %s, ptr @g
  call void @llvm.trap()
  unreachable
}

; So is a block with nothing left in it: there is no instruction to be unsure
; about. The return is the only exit the sequence runs at.
; SEQ-LABEL: clearing sequence for function 'empty_unreachable':
; SEQ-NEXT:  %bb.1 return: clear-stack=not-requested clear-registers=emitted clear-flags=unimplemented
; SEQ-NEXT:  end clearing sequence for function 'empty_unreachable'
define void @empty_unreachable(i32 %x) "zero-call-used-regs"="used-gpr" {
entry:
  %c = icmp sgt i32 %x, 0
  br i1 %c, label %ok, label %bad

ok:
  ret void

bad:
  unreachable
}

; And a call that does not return stays out of scope for a reason of its own:
; the frame is abandoned rather than left, so there is no point at which a
; sequence would run and still be the last thing to touch it. That reason
; survives; only the blocks that had no reason at all have moved.
; SEQ-LABEL: clearing sequence for function 'calls_noreturn':
; SEQ-NEXT:  end clearing sequence for function 'calls_noreturn'
define void @calls_noreturn() "zero-call-used-regs"="used-gpr" {
  call void @abort()
  unreachable
}

declare void @abort() noreturn
