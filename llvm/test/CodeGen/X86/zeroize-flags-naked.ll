; RUN: not llc -mtriple=x86_64-linux-gnu %s -o /dev/null 2>&1 | FileCheck %s
; CHECK: error: {{.*}}"zeroize-flags" cannot be honored on a "naked" function

define void @unsupported() naked "zeroize-flags" {
  unreachable
}
