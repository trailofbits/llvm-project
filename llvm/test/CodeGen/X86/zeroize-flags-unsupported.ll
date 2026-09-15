; RUN: not llc -mtriple=x86_64-linux-gnu %s -o /dev/null 2>&1 | FileCheck %s
; CHECK: error: {{.*}}"zeroize-flags" is not supported by this target or exit protocol

define void @unsupported() "zeroize-flags" {
  ret void
}
