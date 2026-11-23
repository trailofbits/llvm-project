; RUN: llc -mtriple=armv7-unknown-linux-gnueabihf -mattr=-neon -O2 \
; RUN:   -enable-machine-outliner=always -verify-machineinstrs %s -o - | FileCheck %s
; RUN: llc -mtriple=thumbv7m-none-eabi -O2 -verify-machineinstrs %s -o - | FileCheck %s

; Both stack modes must keep the clearing sequence inside the function.
; The unprotected controls confirm the outliner has candidates.

define void @used() #0 {
; CHECK-LABEL: used:
; CHECK-NOT: OUTLINED_FUNCTION
  %slot = alloca <8 x i32>, align 4
  store volatile <8 x i32> <i32 1, i32 2, i32 3, i32 4, i32 5, i32 6, i32 7, i32 8>,
    ptr %slot, align 4
  ret void
}

define void @sensitive() #1 {
; CHECK-LABEL: sensitive:
; CHECK-NOT: OUTLINED_FUNCTION
  %slot = alloca <8 x i32>, align 4
  store volatile <8 x i32> <i32 1, i32 2, i32 3, i32 4, i32 5, i32 6, i32 7, i32 8>,
    ptr %slot, align 4
  ret void
}

define void @unprotected1() #2 {
; CHECK-LABEL: unprotected1:
; CHECK: {{b(l|\.w)?}} OUTLINED_FUNCTION_
  %slot = alloca <8 x i32>, align 4
  store volatile <8 x i32> <i32 1, i32 2, i32 3, i32 4, i32 5, i32 6, i32 7, i32 8>,
    ptr %slot, align 4
  ret void
}

define void @unprotected2() #2 {
; CHECK-LABEL: unprotected2:
; CHECK: {{b(l|\.w)?}} OUTLINED_FUNCTION_
  %slot = alloca <8 x i32>, align 4
  store volatile <8 x i32> <i32 1, i32 2, i32 3, i32 4, i32 5, i32 6, i32 7, i32 8>,
    ptr %slot, align 4
  ret void
}

attributes #0 = { minsize optsize nounwind "zeroize-stack"="used" }
attributes #1 = { minsize optsize nounwind "zeroize-stack"="sensitive" }
attributes #2 = { minsize optsize nounwind }
