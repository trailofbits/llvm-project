; The "zeroize-stack" mode has to come back from bitcode as it went in. A mode
; that parses but is dropped or rewritten on reload would leave a frame cleared
; less thoroughly than the module asked for, with nothing failing to say so, so
; check the reloaded text against the mode written here rather than only that
; reloading succeeds. The second trip pins the first as a fixed point.

; RUN: llvm-as < %s | llvm-dis > %t.ll
; RUN: FileCheck %s < %t.ll
; RUN: llvm-as < %t.ll | llvm-dis > %t2.ll
; RUN: diff %t.ll %t2.ll

define void @used() "zeroize-stack"="used" {
  ret void
}

define void @sensitive() "zeroize-stack"="sensitive" {
  ret void
}

; An unrecognized mode is valid IR that LangRef reads as "used". It has to
; survive verbatim: normalizing it to "used" here would discard what a consumer
; that does know the mode needs, and dropping it would leave the frame with no
; clear at all.
define void @unrecognized_mode() "zeroize-stack"="sensitive-and-then-some" {
  ret void
}

; The mode is per function, so a function without the attribute has to reload
; without one. Handing it a mode would clear a frame nothing asked to clear.
define void @unannotated() {
  ret void
}

; CHECK: define void @used() #[[USED:[0-9]+]]
; CHECK: define void @sensitive() #[[SENSITIVE:[0-9]+]]
; CHECK: define void @unrecognized_mode() #[[UNRECOGNIZED:[0-9]+]]
; CHECK: define void @unannotated() {

; CHECK-DAG: attributes #[[USED]] = { "zeroize-stack"="used" }
; CHECK-DAG: attributes #[[SENSITIVE]] = { "zeroize-stack"="sensitive" }
; CHECK-DAG: attributes #[[UNRECOGNIZED]] = { "zeroize-stack"="sensitive-and-then-some" }
