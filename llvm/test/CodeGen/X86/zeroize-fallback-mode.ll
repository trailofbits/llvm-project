; A "zero-call-used-regs" value that names no known mode means the widest one,
; as LangRef fixes for an unrecognized "zeroize-stack" mode. The mode switch
; previously had no default.

; RUN: llc -mtriple=x86_64-unknown-linux-gnu -verify-machineinstrs %s -o - | FileCheck %s

; An unknown name clears the whole call-used set.
; CHECK-LABEL: unrecognized_mode:
; CHECK:       fldz
; CHECK:       xorl %ecx, %ecx
; CHECK:       xorps %xmm15, %xmm15
; CHECK-NEXT:  retq
define i32 @unrecognized_mode(i32 %x) "zero-call-used-regs"="used-gpr-and-a-mode-from-the-future" {
  ret i32 %x
}

; An empty value reads the same way.
; CHECK-LABEL: empty_mode:
; CHECK:       fldz
; CHECK:       xorl %ecx, %ecx
; CHECK:       xorps %xmm15, %xmm15
; CHECK-NEXT:  retq
define i32 @empty_mode(i32 %x) "zero-call-used-regs"="" {
  ret i32 %x
}

; Omitting the value also requests the widest mode.
; CHECK-LABEL: valueless_mode:
; CHECK:       fldz
; CHECK:       xorl %ecx, %ecx
; CHECK:       xorps %xmm15, %xmm15
; CHECK-NEXT:  retq
define i32 @valueless_mode(i32 %x) "zero-call-used-regs" {
  ret i32 %x
}

; The widest mode written out, for comparison.
; CHECK-LABEL: widest_mode:
; CHECK:       fldz
; CHECK:       xorl %ecx, %ecx
; CHECK:       xorps %xmm15, %xmm15
; CHECK-NEXT:  retq
define i32 @widest_mode(i32 %x) "zero-call-used-regs"="all" {
  ret i32 %x
}

; A recognized mode still means what it says.
; CHECK-LABEL: narrow_mode:
; CHECK:       # %bb.0:
; CHECK-NEXT:  movl %edi, %eax
; CHECK-NEXT:  xorl %edi, %edi
; CHECK-NEXT:  retq
define i32 @narrow_mode(i32 %x) "zero-call-used-regs"="used-gpr" {
  ret i32 %x
}

; "skip" is a name on the scale, so it still means skip.
; CHECK-LABEL: skip_mode:
; CHECK:       # %bb.0:
; CHECK-NEXT:  movl %edi, %eax
; CHECK-NEXT:  retq
define i32 @skip_mode(i32 %x) "zero-call-used-regs"="skip" {
  ret i32 %x
}

; An absent attribute does not request clearing.
; CHECK-LABEL: absent_mode:
; CHECK:       # %bb.0:
; CHECK-NEXT:  movl %edi, %eax
; CHECK-NEXT:  retq
define i32 @absent_mode(i32 %x) {
  ret i32 %x
}
