; Round-trip of the "zeroize-stack" function attribute. The input spells the
; attribute inline on the define and llvm-dis prints it as an attribute group,
; so the second llvm-as is what covers parsing the group form.
; RUN: llvm-as < %s | llvm-dis | llvm-as | llvm-dis | FileCheck %s

define void @used() "zeroize-stack"="used" {
  ret void
}

define void @sensitive() "zeroize-stack"="sensitive" {
  ret void
}

; CHECK: define void @used() #[[USED:[0-9]+]]
; CHECK: define void @sensitive() #[[SENSITIVE:[0-9]+]]

; CHECK-DAG: attributes #[[USED]] = { "zeroize-stack"="used" }
; CHECK-DAG: attributes #[[SENSITIVE]] = { "zeroize-stack"="sensitive" }
