; Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
; SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

; A fixed object and both scalable arguments remain live across a base PCS call.
declare void @fill_fixed(ptr)

define aarch64_sve_vector_pcs <vscale x 16 x i8> @vector_victim(
    <vscale x 16 x i8> %value, <vscale x 16 x i1> %pred, i64 %mode) #0 {
entry:
  %buffer = alloca [80 x i8], align 16
  %first = icmp eq i64 %mode, 0
  br i1 %first, label %early, label %late

early:
  call void @fill_fixed(ptr %buffer)
  %keep = select <vscale x 16 x i1> %pred,
                 <vscale x 16 x i8> %value, <vscale x 16 x i8> zeroinitializer
  ret <vscale x 16 x i8> %keep

late:
  call void @fill_fixed(ptr %buffer)
  %selected = select <vscale x 16 x i1> %pred,
                 <vscale x 16 x i8> %value, <vscale x 16 x i8> zeroinitializer
  %adjust = xor <vscale x 16 x i8> %selected, splat (i8 6)
  ret <vscale x 16 x i8> %adjust
}

define i64 @base_victim(i64 %mode) #0 {
entry:
  %buffer = alloca [80 x i8], align 16
  call void @fill_fixed(ptr %buffer)
  %result = add i64 %mode, 67
  ret i64 %result
}

attributes #0 = { "zeroize-stack"="used" "zero-call-used-regs"="all" "zeroize-flags" }
