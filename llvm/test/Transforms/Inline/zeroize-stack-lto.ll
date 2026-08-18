; The "zeroize-stack" inlining rule has to hold across module boundaries too,
; where the callee reaches the inliner through the LTO link rather than through
; the module it was compiled in. Both regular LTO, which merges the modules
; before optimizing, and ThinLTO, which imports the definition into the caller's
; module, are checked. Each direction of the rule is exercised across the link, so
; that a missing inline is evidence of the rule rather than of nothing being
; inlined at all.

; REQUIRES: x86-registered-target

; RUN: split-file %s %t

;; Regular LTO: one combined module, task 0.
; RUN: llvm-as %t/caller.ll -o %t/caller.bc
; RUN: llvm-as %t/callee.ll -o %t/callee.bc
; RUN: llvm-lto2 run %t/caller.bc %t/callee.bc -save-temps -o %t/lto \
; RUN:   -r %t/caller.bc,call_zeroize_unprotected,plx \
; RUN:   -r %t/caller.bc,call_zeroize_protected,plx \
; RUN:   -r %t/caller.bc,call_plain,plx \
; RUN:   -r %t/caller.bc,zeroize_callee,l \
; RUN:   -r %t/caller.bc,plain_callee,l \
; RUN:   -r %t/callee.bc,zeroize_callee,plx \
; RUN:   -r %t/callee.bc,plain_callee,plx
; RUN: llvm-dis %t/lto.0.4.opt.bc -o - | FileCheck %s

;; ThinLTO: the caller's module is task 1, and the callee is imported into it.
; RUN: opt -module-summary %t/caller.ll -o %t/caller.thin.bc
; RUN: opt -module-summary %t/callee.ll -o %t/callee.thin.bc
; RUN: llvm-lto2 run %t/caller.thin.bc %t/callee.thin.bc -save-temps -o %t/thin \
; RUN:   -r %t/caller.thin.bc,call_zeroize_unprotected,plx \
; RUN:   -r %t/caller.thin.bc,call_zeroize_protected,plx \
; RUN:   -r %t/caller.thin.bc,call_plain,plx \
; RUN:   -r %t/caller.thin.bc,zeroize_callee,l \
; RUN:   -r %t/caller.thin.bc,plain_callee,l \
; RUN:   -r %t/callee.thin.bc,zeroize_callee,plx \
; RUN:   -r %t/callee.thin.bc,plain_callee,plx
; RUN: llvm-dis %t/thin.1.4.opt.bc -o - | FileCheck %s

;; Refused across the link: the caller carries nothing, so there is no clear for
;; the callee's frame bytes to be folded into and the call survives.
; CHECK-LABEL: define {{.*}}@call_zeroize_unprotected(
; CHECK: call i32 @zeroize_callee(
; CHECK-NOT: mul i32 %{{.*}}, 7

;; Permitted across the link: an equally protected caller in the widest mode
;; clears the bytes the callee promised to clear, so the body is folded in.
; CHECK-LABEL: define {{.*}}@call_zeroize_protected(
; CHECK-NOT: call i32 @zeroize_callee(
; CHECK: mul i32 %{{.*}}, 7

;; The unannotated callee is folded into the annotated caller as well.
; CHECK-LABEL: define {{.*}}@call_plain(
; CHECK-NOT: call i32 @plain_callee(
; CHECK: mul i32 %{{.*}}, 11

;--- caller.ll
target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128"
target triple = "x86_64-unknown-linux-gnu"

declare i32 @zeroize_callee(i32)
declare i32 @plain_callee(i32)

define i32 @call_zeroize_unprotected(i32 %x) {
  %r = call i32 @zeroize_callee(i32 %x)
  ret i32 %r
}

define i32 @call_zeroize_protected(i32 %x) "zeroize-stack"="used" {
  %r = call i32 @zeroize_callee(i32 %x)
  ret i32 %r
}

define i32 @call_plain(i32 %x) "zeroize-stack"="used" {
  %r = call i32 @plain_callee(i32 %x)
  ret i32 %r
}

;--- callee.ll
target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128"
target triple = "x86_64-unknown-linux-gnu"

define i32 @zeroize_callee(i32 %x) "zeroize-stack"="used" {
  %r = mul i32 %x, 7
  ret i32 %r
}

define i32 @plain_callee(i32 %x) {
  %r = mul i32 %x, 11
  ret i32 %r
}
