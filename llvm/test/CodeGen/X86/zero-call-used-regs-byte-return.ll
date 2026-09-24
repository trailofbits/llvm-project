; RUN: llc -mtriple=x86_64-unknown-linux-gnu -verify-machineinstrs %s -o - | FileCheck %s --check-prefixes=CHECK,X64
; RUN: llc -mtriple=i386-unknown-linux-gnu -verify-machineinstrs %s -o - | FileCheck %s --check-prefixes=CHECK,X86
; RUN: llc -mtriple=x86_64-unknown-linux-gnu -verify-machineinstrs -filetype=obj %s -o %t.64.o
; RUN: llc -mtriple=i386-unknown-linux-gnu -verify-machineinstrs -filetype=obj %s -o %t.32.o

; Byte division returns the quotient in AL and leaves the remainder in AH.
; Zero-extending AL preserves the quotient while clearing AH and the upper bits.
define i8 @divide_used(i8 %x, i8 %y) "zero-call-used-regs"="used-gpr" {
; CHECK-LABEL: divide_used:
; CHECK: divb
; CHECK-NOT: %{{[er]?ax|al}}
; CHECK: movzbl %al, %eax
; CHECK-NOT: %{{[er]?ax|al}}
; CHECK: ret{{[lq]}}
  %q = udiv i8 %x, %y
  ret i8 %q
}

define i8 @divide_all(i8 %x, i8 %y) "zero-call-used-regs"="all-gpr" {
; CHECK-LABEL: divide_all:
; CHECK: divb
; CHECK-NOT: %{{[er]?ax|al}}
; CHECK: movzbl %al, %eax
; CHECK-NOT: %{{[er]?ax|al}}
; CHECK: ret{{[lq]}}
  %q = udiv i8 %x, %y
  ret i8 %q
}

; A byte clear of AH alone would leave the argument's bits 16-31 in EAX.
define i8 @upper_bits_used(i32 %x) "zero-call-used-regs"="used-gpr" {
; CHECK-LABEL: upper_bits_used:
; X64: movl %edi, %eax
; X64: movzbl %al, %eax
; X86: movzbl 4(%esp), %eax
; CHECK-NOT: %{{[er]?ax|al}}
; CHECK: ret{{[lq]}}
  %t = add i32 %x, 305419776
  %r = trunc i32 %t to i8
  ret i8 %r
}

define i8 @upper_bits_all(i32 %x) "zero-call-used-regs"="all-gpr" {
; CHECK-LABEL: upper_bits_all:
; X64: movl %edi, %eax
; X86: movzbl 4(%esp), %eax
; CHECK: movzbl %al, %eax
; CHECK-NOT: %{{[er]?ax|al}}
; CHECK: ret{{[lq]}}
  %t = add i32 %x, 305419776
  %r = trunc i32 %t to i8
  ret i8 %r
}

; A 64-bit quotient can also leave data in RAX above bit 31.
define i8 @upper_bits_div64(i64 %x, i64 %y) "zero-call-used-regs"="used-gpr" {
; CHECK-LABEL: upper_bits_div64:
; X64: divq
; X86: calll __udivdi3
; CHECK: movzbl %al, %eax
; CHECK-NOT: %{{[er]?ax|al}}
; CHECK: ret{{[lq]}}
  %q = udiv i64 %x, %y
  %r = trunc i64 %q to i8
  ret i8 %r
}

; An undef return byte needs no preserving read. Clear the whole register.
define i8 @return_undef() "zero-call-used-regs"="all-gpr" {
; CHECK-LABEL: return_undef:
; CHECK: xorl %eax, %eax
; CHECK-NOT: %{{[er]?ax|al}}
; CHECK: ret{{[lq]}}
  ret i8 undef
}
