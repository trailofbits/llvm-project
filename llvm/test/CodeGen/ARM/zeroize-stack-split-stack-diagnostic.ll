; RUN: split-file %s %t
; RUN: not llc -mtriple=armv7-linux-gnueabihf -mattr=+neon -verify-machineinstrs \
; RUN:   -verify-cfiinstrs %t/protected.ll -o /dev/null 2>&1 | FileCheck %s \
; RUN:   --implicit-check-not='LLVM ERROR' --implicit-check-not='Stack dump'
; RUN: not llc -mtriple=thumbv7-linux-gnueabihf -mattr=+neon -verify-machineinstrs \
; RUN:   -verify-cfiinstrs %t/protected.ll -o /dev/null 2>&1 | FileCheck %s \
; RUN:   --implicit-check-not='LLVM ERROR' --implicit-check-not='Stack dump'
; RUN: llc -mtriple=armv7-linux-gnueabihf -mattr=+neon -verify-machineinstrs \
; RUN:   -verify-cfiinstrs %t/control.ll -o - | FileCheck %s --check-prefix=CONTROL
; RUN: llc -mtriple=thumbv7-linux-gnueabihf -mattr=+neon -verify-machineinstrs \
; RUN:   -verify-cfiinstrs %t/control.ll -o - | FileCheck %s --check-prefix=CONTROL

; The unsupported request retains its diagnostics. The late clearing-specific
; CFI pass must not reconcile the split-stack prelude's temporary CSR saves.
; CHECK: error: {{.*}}in function stack_only void (): ARM stack clearing does not support
; CHECK: warning: {{.*}}in function stack_only void (): "zeroize-stack" is not supported
; CHECK: error: {{.*}}in function combined void (): ARM stack clearing does not support
; CHECK: warning: {{.*}}in function combined void (): "zeroize-stack" is not supported
; CONTROL-LABEL: ordinary:
; CONTROL: bl __morestack
; CONTROL: bl action

;--- protected.ll

declare void @action(ptr)

define void @stack_only() #0 {
  %words = alloca [6 x i32], align 4
  store volatile i32 7, ptr %words
  call void asm sideeffect "", "~{r4},~{r5},~{r6},~{memory}"()
  call void @action(ptr %words)
  ret void
}

define void @combined() #1 {
  %words = alloca [6 x i32], align 4
  store volatile i32 7, ptr %words
  call void asm sideeffect "", "~{r4},~{r5},~{r6},~{memory}"()
  call void @action(ptr %words)
  ret void
}

attributes #0 = { "frame-pointer"="none" "split-stack" "zeroize-stack"="used" }
attributes #1 = { "frame-pointer"="none" "split-stack" "zeroize-stack"="used"
                  "zero-call-used-regs"="all-gpr" "zeroize-flags" }

;--- control.ll

declare void @action(ptr)

define void @ordinary() #0 {
  %words = alloca [6 x i32], align 4
  store volatile i32 7, ptr %words
  call void asm sideeffect "", "~{r4},~{r5},~{r6},~{memory}"()
  call void @action(ptr %words)
  ret void
}

attributes #0 = { "frame-pointer"="none" "split-stack" }
