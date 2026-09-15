; A block with no successors that ends in an instruction the exit classifier
; cannot account for is in scope: it may leave the function, and a dead
; sequence costs less than an uncleared exit.

; RUN: llc -mtriple=x86_64-unknown-linux-gnu -verify-machineinstrs -pei-print-clearing-sequence %s -o /dev/null 2>&1 | FileCheck --check-prefix=SEQ %s
; RUN: llc -mtriple=x86_64-unknown-linux-gnu -verify-machineinstrs %s -o - | FileCheck %s

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

; A fallback trap must not hide the opaque asm exit before it.
; SEQ-LABEL: clearing sequence for function 'opaque_asm_then_trap':
; SEQ-NEXT:  %bb.0 unknown: clear-stack=not-requested clear-registers=emitted clear-flags=unimplemented
; SEQ-NEXT:  end clearing sequence for function 'opaque_asm_then_trap'
; CHECK-LABEL: opaque_asm_then_trap:
; CHECK:       xorl %r10d, %r10d
; CHECK-NEXT:  #APP
; CHECK-NEXT:  jmp opaque_exit
; CHECK:       ud2
define void @opaque_asm_then_trap() "zero-call-used-regs"="used-gpr" {
  call void asm sideeffect "", "~{r10}"()
  call void asm sideeffect "jmp opaque_exit", "~{memory}"()
  call void @llvm.trap()
  unreachable
}

; A fallback noreturn call must not hide the asm, or lose its own argument.
; SEQ-LABEL: clearing sequence for function 'opaque_asm_then_noreturn':
; SEQ-NEXT:  %bb.0 unknown: clear-stack=not-requested clear-registers=emitted clear-flags=unimplemented
; SEQ-NEXT:  end clearing sequence for function 'opaque_asm_then_noreturn'
; CHECK-LABEL: opaque_asm_then_noreturn:
; CHECK-NOT:   xorl %edi, %edi
; CHECK:       xorl %r10d, %r10d
; CHECK-NEXT:  #APP
; CHECK-NEXT:  jmp opaque_exit
; CHECK-NOT:   xorl %edi, %edi
; CHECK:       callq die
define void @opaque_asm_then_noreturn(i64 %x) "zero-call-used-regs"="used-gpr" {
  call void asm sideeffect "", "~{r10}"()
  call void asm sideeffect "jmp opaque_exit", "~{memory}"()
  call void @die(i64 %x)
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
declare void @die(i64) noreturn
