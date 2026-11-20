; RUN: opt -passes=inline -S %s | FileCheck %s
; RUN: opt -passes=always-inline -S %s | FileCheck %s --check-prefix=ALWAYS
; RUN: opt -passes='default<O2>' -S %s | FileCheck %s

declare void @effect()
define internal void @protected() "zeroize-flags" {
  call void @effect()
  ret void
}
define internal void @forced() alwaysinline "zeroize-flags" {
  call void @effect()
  ret void
}
define void @plain() {
; CHECK-LABEL: define void @plain(
; CHECK: call {{(fastcc )?}}void @protected()
; CHECK: call {{(fastcc )?}}void @forced()
; ALWAYS-LABEL: define void @plain(
; ALWAYS: call {{(fastcc )?}}void @forced()
  call void @protected()
  call void @forced()
  ret void
}
define void @matching() "zeroize-flags" {
; CHECK-LABEL: define void @matching(
; CHECK-NOT: call {{(fastcc )?}}void @protected()
; CHECK-NOT: call {{(fastcc )?}}void @forced()
; CHECK: call void @effect()
; CHECK: call void @effect()
; ALWAYS-LABEL: define void @matching(
; ALWAYS-NOT: call {{(fastcc )?}}void @forced()
; ALWAYS: call void @effect()
  call void @protected()
  call void @forced()
  ret void
}
