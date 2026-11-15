; RUN: not llc -mtriple=x86_64-unknown-linux-gnu -mattr=-sahf %s -o /dev/null 2>&1 | FileCheck %s
; RUN: not llc -mtriple=x86_64-pc-windows-msvc -mattr=+sahf %s -o /dev/null 2>&1 | FileCheck %s
; RUN: not llc -mtriple=i386-unknown-linux-gnu %s -o /dev/null 2>&1 | FileCheck %s
; RUN: not llc -mtriple=x86_64-unknown-linux-gnu -mattr=+sahf,+lvi-cfi \
; RUN:   %s -o /dev/null 2>&1 | FileCheck %s

; CHECK: error: {{.*}}"zeroize-flags" is not supported by this target or exit protocol
define void @unsupported() "zeroize-flags" {
  ret void
}
