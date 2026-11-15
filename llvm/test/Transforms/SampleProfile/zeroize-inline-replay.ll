; RUN: split-file %s %t
; RUN: opt -passes=sample-profile -verify-each -sample-profile-file=%t/profile \
; RUN:   -sample-profile-merge-inlinee -sample-profile-top-down-load \
; RUN:   -S %t/input.ll | FileCheck %s
; RUN: opt -passes=sample-profile -verify-each -sample-profile-file=%t/profile \
; RUN:   -sample-profile-merge-inlinee -sample-profile-top-down-load \
; RUN:   -sample-profile-inline-replay=%t/replay -sample-profile-inline-replay-scope=Module \
; RUN:   -S %t/input.ll | FileCheck %s

; CHECK-LABEL: define i32 @caller(
; CHECK: call i32 @callee(

;--- input.ll
define i32 @callee(i32 %x) "use-sample-profile" "zeroize-stack"="used" "zeroize-flags" !dbg !4 {
  %p = alloca i32
  store volatile i32 %x, ptr %p, !dbg !6
  ret i32 %x, !dbg !6
}

define i32 @caller(i32 %x) "use-sample-profile" !dbg !5 {
  %r = call i32 @callee(i32 %x), !dbg !7
  ret i32 %r, !dbg !7
}

!llvm.dbg.cu = !{!0}
!llvm.module.flags = !{!3}
!0 = distinct !DICompileUnit(language: DW_LANG_C, file: !1, producer: "test",
                            isOptimized: true, runtimeVersion: 0,
                            emissionKind: LineTablesOnly)
!1 = !DIFile(filename: "zeroize.c", directory: ".")
!2 = !DISubroutineType(types: !8)
!3 = !{i32 2, !"Debug Info Version", i32 3}
!4 = distinct !DISubprogram(name: "callee", scope: !1, file: !1, line: 1,
                           type: !2, scopeLine: 1,
                           spFlags: DISPFlagDefinition, unit: !0)
!5 = distinct !DISubprogram(name: "caller", scope: !1, file: !1, line: 10,
                           type: !2, scopeLine: 10,
                           spFlags: DISPFlagDefinition, unit: !0)
!6 = !DILocation(line: 2, scope: !4)
!7 = !DILocation(line: 11, scope: !5)
!8 = !{}

;--- profile
caller:1000:1000
 1: callee:1000
  1: 1000
callee:1000:1000
 1: 1000

;--- replay
remark: zeroize.c:11:0: 'callee' inlined into 'caller' at callsite caller:1:0;
