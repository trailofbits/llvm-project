; Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
; SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

declare void @fill_fixed(ptr)
declare void @llvm.aarch64.sve.setffr()
define aarch64_sve_vector_pcs <vscale x 16 x i1> @vector_victim(
    <vscale x 16 x i8> %value, <vscale x 16 x i1> %pred, i64 %mode) #0 {
  %buffer = alloca [80 x i8], align 16
  call void @fill_fixed(ptr %buffer)
  call void @llvm.aarch64.sve.setffr()
  ret <vscale x 16 x i1> %pred
}
define i64 @base_victim(i64 %mode) #0 {
  %buffer = alloca [80 x i8], align 16
  call void @fill_fixed(ptr %buffer)
  call void @llvm.aarch64.sve.setffr()
  %result = add i64 %mode, 67
  ret i64 %result
}
attributes #0 = { "zeroize-stack"="used" "zero-call-used-regs"="used" "zeroize-flags" }
