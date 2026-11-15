; RUN: llc -mtriple=x86_64-unknown-linux-gnu -O0 -verify-machineinstrs %s -o - | FileCheck %s
; RUN: llc -mtriple=x86_64-unknown-linux-gnu -O2 -verify-machineinstrs %s -o - | FileCheck %s
; RUN: llc -mtriple=x86_64-unknown-linux-gnu -filetype=obj %s -o /dev/null

; Clear the exact naturally aligned red-zone extent, without reaching the
; return-address slot or extending below the function's owned storage.
define i64 @byte_red_zone(i64 %x) "zeroize-stack"="used" {
; CHECK-LABEL: byte_red_zone:
; CHECK: movq %rdi, %rax
; CHECK: movb $42, -1(%rsp)
; CHECK: movb $0, -1(%rsp)
; CHECK-NEXT: retq
  %p = alloca i8, align 1
  store volatile i8 42, ptr %p
  ret i64 %x
}

define i64 @half_red_zone(i64 %x) "zeroize-stack"="used" {
; CHECK-LABEL: half_red_zone:
; CHECK: movq %rdi, %rax
; CHECK: movw $42, -2(%rsp)
; CHECK: movw $0, -2(%rsp)
; CHECK-NEXT: retq
  %p = alloca i16, align 2
  store volatile i16 42, ptr %p
  ret i64 %x
}

define i64 @word_red_zone(i64 %x) "zeroize-stack"="used" {
; CHECK-LABEL: word_red_zone:
; CHECK: movq %rdi, %rax
; CHECK: movl $42, -4(%rsp)
; CHECK: movl $0, -4(%rsp)
; CHECK-NEXT: retq
  %p = alloca i32, align 4
  store volatile i32 42, ptr %p
  ret i64 %x
}

; Without the red zone, clear exactly the allocated bytes before releasing
; them. The incoming return address remains just above that allocation.
define i64 @byte_no_red_zone(i64 %x) noredzone "zeroize-stack"="used" {
; CHECK-LABEL: byte_no_red_zone:
; CHECK: movq %rdi, %rax
; CHECK: movb $0, (%rsp)
; CHECK-NEXT: {{(incq|leaq)}}
; CHECK-NEXT: .cfi_def_cfa %rsp, 8
; CHECK-NEXT: retq
  %p = alloca i8, align 1
  store volatile i8 42, ptr %p
  ret i64 %x
}

define i64 @half_no_red_zone(i64 %x) noredzone "zeroize-stack"="used" {
; CHECK-LABEL: half_no_red_zone:
; CHECK: movq %rdi, %rax
; CHECK: movw $0, (%rsp)
; CHECK-NEXT: {{(addq|leaq)}}
; CHECK-NEXT: .cfi_def_cfa %rsp, 8
; CHECK-NEXT: retq
  %p = alloca i16, align 2
  store volatile i16 42, ptr %p
  ret i64 %x
}

define i64 @word_no_red_zone(i64 %x) noredzone "zeroize-stack"="used" {
; CHECK-LABEL: word_no_red_zone:
; CHECK: movq %rdi, %rax
; CHECK: movl $0, (%rsp)
; CHECK-NEXT: {{(addq|leaq)}}
; CHECK-NEXT: .cfi_def_cfa %rsp, 8
; CHECK-NEXT: retq
  %p = alloca i32, align 4
  store volatile i32 42, ptr %p
  ret i64 %x
}
