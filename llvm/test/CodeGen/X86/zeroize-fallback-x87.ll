; The x87 register file is a stack, and the clearer fills its free slots with
; pushes. The exit instruction says how many slots are live: a return carries
; its returned values as implicit ST uses, a call leaves the stack empty, and
; X86FloatingPoint records every entry live across an inline asm as an ST use.
; Pushing over a live entry would overflow the stack and turn it into NaN. The
; pop X86FloatingPoint appends after an asm cannot transfer control, so it does
; not move the exit past the asm.

; RUN: llc -mtriple=x86_64-unknown-linux-gnu %s -o - | FileCheck %s

; An asm with nothing on the stack gets the full clear in front of it.
; CHECK-LABEL: asm_empty_stack:
; CHECK:       fstpt
; CHECK-COUNT-8: fldz
; CHECK-COUNT-8: fstp %st(0)
; CHECK:       xorl %eax, %eax
; CHECK:       #APP
; CHECK-NEXT:  jmp opaque_exit
define void @asm_empty_stack(x86_fp80 %x, ptr %mem) "zero-call-used-regs"="all" {
  store volatile x86_fp80 %x, ptr %mem
  call void asm sideeffect "jmp opaque_exit", "~{memory}"()
  unreachable
}

; One live input the asm consumes: seven pushes, the input left alone.
; CHECK-LABEL: asm_st_input:
; CHECK-COUNT-7: fldz
; CHECK-NOT:   fldz
; CHECK:       #APP
; CHECK-NEXT:  hlt
define void @asm_st_input(x86_fp80 %x) "zero-call-used-regs"="all" {
  call void asm sideeffect "hlt", "{st},~{st},~{memory}"(x86_fp80 %x)
  unreachable
}

; The asm leaves its input on the stack, so X86FloatingPoint pops it after the
; asm. The sequence still goes in front of the asm, not in front of the pop.
; CHECK-LABEL: asm_st_input_popped_after:
; CHECK-COUNT-7: fldz
; CHECK-NOT:   fldz
; CHECK:       xorl %eax, %eax
; CHECK:       #APP
; CHECK-NEXT:  hlt
; CHECK-NEXT:  #NO_APP
; CHECK-NEXT:  fstp %st(0)
define void @asm_st_input_popped_after(x86_fp80 %x) "zero-call-used-regs"="all" {
  call void asm sideeffect "hlt", "{st},~{memory}"(x86_fp80 %x)
  unreachable
}

; The same with an "f" input and an asm that jumps out of the function, in a
; mode without x87: the clear of a register the asm does not use runs before
; the jump, not after it.
; CHECK-LABEL: asm_f_input_jumps:
; CHECK:       movq $12345, %r10
; CHECK:       xorl %r10d, %r10d
; CHECK:       #APP
; CHECK-NEXT:  jmp opaque_exit
; CHECK-NEXT:  #NO_APP
; CHECK-NEXT:  fstp %st(0)
define void @asm_f_input_jumps(x86_fp80 %x) "zero-call-used-regs"="used-gpr" {
  call void asm sideeffect "movq $$12345, %r10", "~{r10},~{memory}"()
  call void asm sideeffect "jmp opaque_exit", "f,~{memory}"(x86_fp80 %x)
  unreachable
}

; Two live inputs: six pushes.
; CHECK-LABEL: asm_two_inputs:
; CHECK-COUNT-6: fldz
; CHECK-NOT:   fldz
; CHECK:       #APP
; CHECK-NEXT:  hlt
define void @asm_two_inputs(x86_fp80 %x, x86_fp80 %y) "zero-call-used-regs"="all" {
  call void asm sideeffect "hlt", "{st},{st(1)},~{memory}"(x86_fp80 %x, x86_fp80 %y)
  unreachable
}

; A value used after the asm sits on the stack below the asm's input. Both are
; live across the asm, so six pushes.
; CHECK-LABEL: asm_value_live_across:
; CHECK-COUNT-6: fldz
; CHECK-NOT:   fldz
; CHECK:       #APP
; CHECK-NEXT:  hlt
; CHECK:       fstpt
define void @asm_value_live_across(x86_fp80 %x, x86_fp80 %y, ptr %mem) "zero-call-used-regs"="all" {
  %v = fadd x86_fp80 %y, 0xK3FFF8000000000000000
  call void asm sideeffect "hlt", "f,~{memory}"(x86_fp80 %x)
  store volatile x86_fp80 %v, ptr %mem
  unreachable
}

; An x87 store cannot transfer control, so a block it ends is not an exit and
; gets no sequence at all.
; CHECK-LABEL: fstp_then_unreachable:
; CHECK-NOT:   fldz
; CHECK-NOT:   xorl
; CHECK:       fstpt
define void @fstp_then_unreachable(x86_fp80 %x) "zero-call-used-regs"="all" {
  %r = fadd x86_fp80 %x, 0xK3FFF8000000000000000
  store volatile x86_fp80 %r, ptr @g
  unreachable
}

; A return still clears the x87 stack, sparing the returned value.
; CHECK-LABEL: ret_fp80:
; CHECK-COUNT-7: fldz
; CHECK-COUNT-7: fstp %st(0)
; CHECK:       retq
define x86_fp80 @ret_fp80(x86_fp80 %x) "zero-call-used-regs"="all" {
  %r = fadd x86_fp80 %x, 0xK3FFF8000000000000000
  ret x86_fp80 %r
}

@g = external global x86_fp80
