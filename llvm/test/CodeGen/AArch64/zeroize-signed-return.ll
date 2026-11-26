; RUN: llc -mtriple=aarch64-linux-gnu -mattr=+pauth -verify-machineinstrs %s -o - | FileCheck %s
; RUN: llc -mtriple=aarch64-linux-gnu -mattr=+pauth -O0 -verify-machineinstrs %s -o - | FileCheck %s
; RUN: llc -mtriple=aarch64-linux-gnu -mattr=+pauth -verify-machineinstrs -filetype=obj %s -o %t
; RUN: not llc -mtriple=aarch64-linux-gnu -mattr=-pauth %s -o /dev/null 2>&1 | FileCheck %s --check-prefix=NO-PAUTH

; NO-PAUTH: in function leaf {{.*}}"zeroize-flags" is not supported
; CHECK-LABEL: leaf:
; CHECK: paciasp
; CHECK: mov x1, #0
; CHECK: msr NZCV, xzr
; CHECK-NEXT: retaa
define i64 @leaf(i64 %result) #0 {
  ret i64 %result
}

; The clearing loop creates a new return block. Authenticate with the entry SP
; after restoring LR, erasing the frame, and preserving the call's result.
; CHECK-LABEL: nonleaf:
; CHECK: pacibsp
; CHECK: bl consume
; CHECK: ldr x30,
; CHECK: stp xzr, xzr,
; CHECK: mov sp,
; CHECK: msr NZCV, xzr
; CHECK-NEXT: retab
define i64 @nonleaf() #1 {
  %buf = alloca [128 x i8], align 16
  %result = call i64 @consume(ptr %buf)
  ret i64 %result
}

declare i64 @consume(ptr)
attributes #0 = { "sign-return-address"="all" "zeroize-stack"="used" "zero-call-used-regs"="all" "zeroize-flags" }
attributes #1 = { "sign-return-address"="non-leaf" "sign-return-address-key"="b_key" "zeroize-stack"="used" "zero-call-used-regs"="all" "zeroize-flags" }
