; A block with no successors that ends in an instruction the exit classifier
; cannot account for is in scope: it may leave the function, and a dead
; sequence costs less than an uncleared exit.
; trailofbits/vspells-ct-internal-notes#24.

; RUN: llc -mtriple=x86_64-unknown-linux-gnu -pei-print-clearing-sequence %s -o /dev/null 2>&1 | FileCheck --check-prefix=SEQ %s
; RUN: llc -mtriple=x86_64-unknown-linux-gnu %s -o - | FileCheck %s

@g = external global i64

declare void @llvm.trap()

; Inline asm ending the block may jump or not come back. The sequence goes in
; front of it and spares the registers the asm declares.
; SEQ-LABEL: clearing sequence for function 'opaque_asm':
; SEQ-NEXT:  %bb.0 unknown: clear-stack=not-requested clear-registers=emitted clear-flags=unimplemented
; SEQ-NEXT:  end clearing sequence for function 'opaque_asm'
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

; A trap is marked by the target as where control stops, so it stays out of
; scope.
; SEQ-LABEL: clearing sequence for function 'traps':
; SEQ-NEXT:  end clearing sequence for function 'traps'
; CHECK-LABEL: traps:
; CHECK-NOT:   xorl
; CHECK:       ud2
define void @traps(i64 %a, i64 %b) "zero-call-used-regs"="used-gpr" {
  %s = add i64 %a, %b
  store i64 %s, ptr @g
  call void @llvm.trap()
  unreachable
}

; An empty block has nothing to be unsure about; the return is the only exit.
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

; A call that does not return abandons the frame and stays out of scope.
; SEQ-LABEL: clearing sequence for function 'calls_noreturn':
; SEQ-NEXT:  end clearing sequence for function 'calls_noreturn'
define void @calls_noreturn() "zero-call-used-regs"="used-gpr" {
  call void @abort()
  unreachable
}

declare void @abort() noreturn
