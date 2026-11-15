; RUN: split-file %s %t
; RUN: not opt -passes=place-safepoints -verify-each -S %t/stack.ll -o /dev/null \
; RUN:   2>&1 | FileCheck %s --check-prefix=STACK
; RUN: not opt -passes=place-safepoints -verify-each -S %t/flags.ll -o /dev/null \
; RUN:   2>&1 | FileCheck %s --check-prefix=FLAGS
; RUN: opt -passes=place-safepoints -verify-each -S %t/compatible.ll \
; RUN:   | FileCheck %s --check-prefix=COMPATIBLE

; STACK: error: cannot inline gc.safepoint_poll: incompatible zeroize-stack attributes
; FLAGS: error: cannot inline gc.safepoint_poll: incompatible zeroize-flags attributes
; COMPATIBLE-LABEL: define void @caller()
; COMPATIBLE: call void @do_safepoint()
; COMPATIBLE-NOT: call void @gc.safepoint_poll()
; COMPATIBLE: ret void

;--- stack.ll
define void @caller() gc "statepoint-example" { ret void }
declare void @do_safepoint()
define void @gc.safepoint_poll() "zeroize-stack"="used" {
  call void @do_safepoint()
  ret void
}

;--- flags.ll
define void @caller() gc "statepoint-example" { ret void }
declare void @do_safepoint()
define void @gc.safepoint_poll() "zeroize-flags" {
  call void @do_safepoint()
  ret void
}

;--- compatible.ll
define void @caller() "zeroize-stack"="used" "zeroize-flags" gc "statepoint-example" {
  ret void
}
declare void @do_safepoint()
define void @gc.safepoint_poll() "zeroize-stack"="used" "zeroize-flags" {
  call void @do_safepoint()
  ret void
}
