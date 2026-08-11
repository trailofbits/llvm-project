; The "zeroize-stack" attribute names how much of the frame is cleared, so it
; has to carry a value. Both spellings of "no value" are the same attribute
; once parsed, and neither names a mode.
;
; An unrecognized mode is deliberately not an error: LangRef gives it the
; meaning of "used". llvm/test/Bitcode/zeroize-stack-attribute.ll covers that.

; RUN: not llvm-as < %s -o /dev/null 2>&1 | FileCheck %s

; CHECK: "zeroize-stack" attribute must name a mode
; CHECK: ptr @no_value
define void @no_value() #0 {
  ret void
}

; CHECK: "zeroize-stack" attribute must name a mode
; CHECK: ptr @empty_value
define void @empty_value() #1 {
  ret void
}

attributes #0 = { "zeroize-stack" }
attributes #1 = { "zeroize-stack"="" }
