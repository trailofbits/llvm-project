; RUN: llc -mtriple=x86_64-unknown-linux-gnu -mattr=+sahf \
; RUN:   -verify-machineinstrs %s -o - | FileCheck %s
; RUN: llc -mtriple=x86_64-unknown-linux-gnu -mattr=+sahf -filetype=obj %s -o /dev/null

; The aligned slot is cleared; the return address at (%rsp) is excluded.
define i64 @red_zone(i64 %x) "zeroize-stack"="used" {
; CHECK-LABEL: red_zone:
; CHECK: movb $42, -8(%rsp)
; CHECK: movq $0, -8(%rsp)
; CHECK-NEXT: retq
  %p = alloca i8, align 8
  store volatile i8 42, ptr %p
  ret i64 %x
}

define i64 @allocated_frame(i64 %x) noredzone "zeroize-stack"="used" {
; CHECK-LABEL: allocated_frame:
; CHECK: movq $0, (%rsp)
; CHECK-NEXT: addq $8, %rsp
; CHECK-NEXT: .cfi_def_cfa %rsp, 8
; CHECK-NEXT: retq
  %p = alloca i64, align 8
  store volatile i64 %x, ptr %p
  ret i64 %x
}

; Saved frame-pointer storage and padding remain owned until after the clear.
define i64 @frame_pointer(i64 %x) noredzone uwtable "frame-pointer"="all" "zeroize-stack"="used" {
; CHECK-LABEL: frame_pointer:
; CHECK: .cfi_def_cfa %rsp, 24
; CHECK-NEXT: movq 8(%rsp), %rbp
; CHECK-NEXT: .cfi_restore %rbp
; CHECK-NEXT: movq $0, (%rsp)
; CHECK-NEXT: movq $0, 8(%rsp)
; CHECK-NEXT: addq $16, %rsp
; CHECK-NEXT: .cfi_def_cfa %rsp, 8
; CHECK-NEXT: retq
  %p = alloca i64, align 8
  store volatile i64 %x, ptr %p
  ret i64 %x
}

declare void @consume(ptr)
define i64 @saved_registers(i64 %x) uwtable "zeroize-stack"="used" {
; CHECK-LABEL: saved_registers:
; CHECK: callq consume
; CHECK: movq {{[0-9]+}}(%rsp), %rbx
; CHECK: .cfi_restore %rbx
; CHECK: movq {{[0-9]+}}(%rsp), %r12
; CHECK: .cfi_restore %r12
; CHECK: movq $0, (%rsp)
; CHECK: addq $40, %rsp
; CHECK: .cfi_def_cfa %rsp, 8
; CHECK-NEXT: retq
  %p = alloca i64, align 8
  store volatile i64 %x, ptr %p
  call void asm sideeffect "", "~{rbx},~{r12}"()
  call void @consume(ptr %p)
  ret i64 %x
}

; Loops have fixed frame-size bounds and clear their address/count temporaries.
define i64 @large_frame(i64 %x) "zeroize-stack"="used" "zero-call-used-regs"="skip" {
; CHECK-LABEL: large_frame:
; CHECK: callq consume
; CHECK: leaq (%rsp), %r11
; CHECK: movq ${{[0-9]+}}, %r10
; CHECK: [[LOOP:.LBB[0-9]+_[0-9]+]]:
; CHECK: movq $0, (%r11)
; CHECK-NEXT: addq $8, %r11
; CHECK-NEXT: subq $8, %r10
; CHECK-NEXT: jne [[LOOP]]
; CHECK: addq $4104, %rsp
; CHECK-DAG: xorl %r10d, %r10d
; CHECK-DAG: xorl %r11d, %r11d
; CHECK: retq
  %p = alloca [4096 x i8], align 16
  call void @consume(ptr %p)
  ret i64 %x
}

define i64 @stack_then_flags(i64 %x) "zeroize-stack"="used" "zeroize-flags" {
; CHECK-LABEL: stack_then_flags:
; CHECK: movq $0, -8(%rsp)
; CHECK-NEXT: xorl %r11d, %r11d
; CHECK-NEXT: xchgq %r11, %rax
; CHECK-NEXT: testl %eax, %eax
; CHECK-NEXT: sahf
; CHECK-NEXT: xchgq %r11, %rax
; CHECK-NEXT: retq
  %p = alloca i64, align 8
  store volatile i64 %x, ptr %p
  ret i64 %x
}
