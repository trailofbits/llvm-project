; The "zeroize-stack" attribute is accepted whatever it says, and that is the
; intent rather than a gap: an absent value, an empty value, and a mode this
; version of LLVM does not recognize all mean "used", the widest mode. A value
; the IR cannot interpret therefore widens what is cleared instead of failing,
; so a producer naming a mode a consumer has not learned loses no protection.
;
; Both spellings of "no value" are the same attribute once parsed, so both
; survive the round-trip and both land in the same attribute group.
;
; llvm/test/Bitcode/zeroize-stack-attribute.ll covers the unrecognized mode.

; RUN: llvm-as < %s | llvm-dis | FileCheck %s

; CHECK: define void @no_value() #[[ATTRS:[0-9]+]]
define void @no_value() #0 {
  ret void
}

; CHECK: define void @empty_value() #[[ATTRS]]
define void @empty_value() #1 {
  ret void
}

; CHECK: attributes #[[ATTRS]] = {{.*}}"zeroize-stack"
attributes #0 = { "zeroize-stack" }
attributes #1 = { "zeroize-stack"="" }
