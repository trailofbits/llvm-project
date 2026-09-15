; RUN: not llc -mtriple=thumbv5-none-eabi %s -o /dev/null 2>&1 | FileCheck %s
; RUN: not llc -mtriple=thumbv7-windows-msvc %s -o /dev/null 2>&1 | FileCheck %s
; CHECK: error: {{.*}}"zeroize-flags" is not supported by this target or exit protocol

define void @unsupported() "zeroize-flags" { ret void }
