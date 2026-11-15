; RUN: not llc -mtriple=x86_64-unknown-linux-gnu -mattr=+sahf %s -o /dev/null 2>&1 | FileCheck %s

declare i64 @callee(i64)

; CHECK: error: {{.*}}X86 stack or flags clearing does not support musttail
define i64 @flags_musttail(i64 %x) "zeroize-flags" {
  %r = musttail call i64 @callee(i64 %x)
  ret i64 %r
}
