; The modes of "zero-call-used-regs" are a scale, from clearing nothing to
; clearing everything call-used. A value that is not one of the names on the
; scale carries no information about where on it the producer meant to be, and
; the only reading that cannot clear less than was asked for is the widest one.
;
; This is the reading LangRef already fixes for an unrecognized "zeroize-stack"
; mode, and the two attributes now agree. Before, the mode switch had no
; default at all: an assertion in a build that has them, and in a release
; compiler an uninitialized mode deciding what gets cleared.
;
; trailofbits/vspells-ct-internal-notes#24.

; RUN: llc -mtriple=x86_64-unknown-linux-gnu %s -o - | FileCheck %s

; A name this version of LLVM does not know. It clears the whole call-used set:
; the general-purpose registers, the vector registers and the x87 stack.
; CHECK-LABEL: unrecognized_mode:
; CHECK:       fldz
; CHECK:       xorl %ecx, %ecx
; CHECK:       xorps %xmm15, %xmm15
; CHECK-NEXT:  retq
define i32 @unrecognized_mode(i32 %x) "zero-call-used-regs"="used-gpr-and-a-mode-from-the-future" {
  ret i32 %x
}

; A value that names nothing at all reads the same way. There is no mode here
; to be narrower than "all" either.
; CHECK-LABEL: empty_mode:
; CHECK:       fldz
; CHECK:       xorl %ecx, %ecx
; CHECK:       xorps %xmm15, %xmm15
; CHECK-NEXT:  retq
define i32 @empty_mode(i32 %x) "zero-call-used-regs"="" {
  ret i32 %x
}

; The widest mode written out, for comparison: this is what the two above
; resolve to.
; CHECK-LABEL: widest_mode:
; CHECK:       fldz
; CHECK:       xorl %ecx, %ecx
; CHECK:       xorps %xmm15, %xmm15
; CHECK-NEXT:  retq
define i32 @widest_mode(i32 %x) "zero-call-used-regs"="all" {
  ret i32 %x
}

; A mode that is recognized still means what it says. Widening applies to what
; could not be read, not to everything.
; CHECK-LABEL: narrow_mode:
; CHECK:       # %bb.0:
; CHECK-NEXT:  movl %edi, %eax
; CHECK-NEXT:  xorl %edi, %edi
; CHECK-NEXT:  retq
define i32 @narrow_mode(i32 %x) "zero-call-used-regs"="used-gpr" {
  ret i32 %x
}

; And "skip" is a name on the scale, not a failure to read one, so it keeps
; meaning skip. An unrecognized mode is the one case that has to widen, because
; it is the only one where nothing was said.
; CHECK-LABEL: skip_mode:
; CHECK:       # %bb.0:
; CHECK-NEXT:  movl %edi, %eax
; CHECK-NEXT:  retq
define i32 @skip_mode(i32 %x) "zero-call-used-regs"="skip" {
  ret i32 %x
}
