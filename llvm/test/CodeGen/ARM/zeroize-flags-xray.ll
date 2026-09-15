; RUN: split-file %s %t
; RUN: not llc -mtriple=armv7-unknown-linux-gnueabihf -stop-after=prolog-epilog \
; RUN:   %t/instrumented.ll -o /dev/null 2>&1 | FileCheck %s --check-prefix=DIAG
; RUN: llc -mtriple=armv7-unknown-linux-gnueabihf -verify-machineinstrs \
; RUN:   %t/never.ll -o - | FileCheck %s --check-prefix=NEVER --implicit-check-not=xray

; XRay exit instrumentation can change flags after PEI's final flags clear.
; DIAG: error: {{.*}}in function always {{.*}}"zeroize-flags" is not supported
; DIAG: error: {{.*}}in function threshold {{.*}}"zeroize-flags" is not supported

;--- instrumented.ll
define void @always() "zeroize-flags" "function-instrument"="xray-always" {
  ret void
}

define void @threshold() "zeroize-flags" "xray-instruction-threshold"="1" {
  ret void
}

;--- never.ll
; NEVER-LABEL: never:
; NEVER: mov r0, #0
; NEVER-NEXT: uadd8 r0, r0, r0
; NEVER-NEXT: msr APSR_nzcvq, r0
; NEVER-NEXT: bx lr
define void @never() "zeroize-flags" #0 {
  ret void
}

attributes #0 = {
  "function-instrument"="xray-never" "xray-instruction-threshold"="1"
}
