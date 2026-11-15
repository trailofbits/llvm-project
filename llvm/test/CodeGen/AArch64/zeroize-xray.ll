; RUN: split-file %s %t
; RUN: not llc -mtriple=aarch64-unknown-linux-gnu %t/attributes.ll -o /dev/null 2>&1 | FileCheck \
; RUN: %s --check-prefix=ATTR
; RUN: not llc -mtriple=aarch64-unknown-linux-gnu -stop-after=prolog-epilog %t/events.ll -o \
; RUN: /dev/null 2>&1 | FileCheck %s --check-prefix=EVENT
; RUN: llc -mtriple=aarch64-unknown-linux-gnu -verify-machineinstrs %t/never.ll -o - | FileCheck \
; RUN: %s --check-prefix=NEVER
; RUN: llc -mtriple=aarch64-unknown-linux-gnu -stop-after=prolog-epilog -verify-machineinstrs \
; RUN: %t/flags-event.ll -o - | FileCheck %s --check-prefix=FLAGS

; XRay inserts exit instrumentation after frame and flags clearing. A threshold
; can select instrumentation after PEI, so it also needs an explicit diagnostic.
; ATTR: error: {{.*}}in function always {{.*}}AArch64 stack clearing does not support
; ATTR: error: {{.*}}in function always {{.*}}"zeroize-flags" is not supported
; ATTR: error: {{.*}}in function threshold {{.*}}AArch64 stack clearing does not support
; ATTR: error: {{.*}}in function threshold {{.*}}"zeroize-flags" is not supported

;--- attributes.ll
define void @always() "function-instrument"="xray-always" "zeroize-stack"="used" "zeroize-flags" {
  ret void
}

define void @threshold() "xray-instruction-threshold"="1" "zeroize-stack"="used" "zeroize-flags" {
  ret void
}

; Custom events can use stack storage outside the frame tracked by PEI even
; when function entry/exit instrumentation is disabled.
; EVENT: error: {{.*}}in function custom {{.*}}AArch64 stack clearing does not support
; EVENT: error: {{.*}}in function typed {{.*}}AArch64 stack clearing does not support

;--- events.ll
declare void @llvm.xray.customevent(ptr, i64)
declare void @llvm.xray.typedevent(i64, ptr, i64)

define void @custom(ptr %p, i64 %n) "function-instrument"="xray-never" "zeroize-stack"="used" {
  call void @llvm.xray.customevent(ptr %p, i64 %n)
  ret void
}

define void @typed(ptr %p, i64 %n) "function-instrument"="xray-never" "zeroize-stack"="used" {
  call void @llvm.xray.typedevent(i64 1, ptr %p, i64 %n)
  ret void
}

; An explicit opt-out wins over a threshold and retains ordinary clearing.
; NEVER-LABEL: never:
; NEVER: stp xzr, xzr
; NEVER: mov sp, x9
; NEVER: msr NZCV, xzr
; NEVER-NEXT: ret

;--- never.ll
define void @never()
    "function-instrument"="xray-never" "xray-instruction-threshold"="0"
    "zeroize-stack"="used" "zeroize-flags" {
  %p = alloca i64, align 8
  store volatile i64 0, ptr %p
  ret void
}

; Body events do not interfere with exit flags clearing by itself.
; FLAGS: PATCHABLE_EVENT_CALL
; FLAGS: MSR 55824, $xzr, implicit-def $nzcv
; FLAGS: RET_ReallyLR

;--- flags-event.ll
declare void @llvm.xray.customevent(ptr, i64)

define void @flags_event(ptr %p, i64 %n) "function-instrument"="xray-never" "zeroize-flags" {
  call void @llvm.xray.customevent(ptr %p, i64 %n)
  ret void
}
