; RUN: llc -mtriple=armv7-none-eabi -O0 -enable-tail-merge=false -verify-cfiinstrs \
; RUN:   -exception-model=dwarf -verify-machineinstrs -filetype=obj %s -o %t.arm
; RUN: llvm-objdump -d --no-show-raw-insn %t.arm > %t.arm.dump
; RUN: llvm-dwarfdump --eh-frame %t.arm >> %t.arm.dump
; RUN: FileCheck %s --input-file=%t.arm.dump
; RUN: llc -mtriple=thumbv6m-none-eabi -O0 -enable-tail-merge=false -verify-cfiinstrs \
; RUN:   -force-dwarf-frame-section -verify-machineinstrs -filetype=obj %s -o %t.thumb
; RUN: llvm-objdump -d --no-show-raw-insn %t.thumb > %t.thumb.dump
; RUN: llvm-dwarfdump --debug-frame %t.thumb >> %t.thumb.dump
; RUN: FileCheck %s --input-file=%t.thumb.dump

; At the sibling call the frame pointer and LR are still saved, even though
; the preceding block in address order released its frame and returned.
; Match instruction addresses against .eh_frame on ARM and .debug_frame on
; Thumb with its native EHABI exception tables.
; CHECK-LABEL: <two_returns>:
; CHECK: mov sp,
; CHECK-NEXT: [[FIRST_RELEASED:[0-9a-f]+]]:
; CHECK: bx lr
; CHECK-NEXT: [[CALL:[0-9a-f]+]]: bl
; CHECK: mov sp,
; CHECK-NEXT: [[SECOND_RELEASED:[0-9a-f]+]]:
; CHECK: bx lr

; CHECK: FDE cie=
; CHECK: CFA=[[FP:R7|R11]]+8: [[FP]]=[CFA-8], LR=[CFA-4]
; CHECK: 0x[[FIRST_RELEASED]]: CFA=SP{{$}}
; CHECK-NEXT: 0x[[CALL]]: CFA=[[FP]]+8: [[FP]]=[CFA-8], LR=[CFA-4]
; CHECK: 0x[[SECOND_RELEASED]]: CFA=SP{{$}}
; CHECK-NOT: CFA=

declare void @later()

define i32 @two_returns(i1 %choose) uwtable "frame-pointer"="all" "zeroize-stack"="used" {
entry:
  %local = alloca [80 x i8], align 4
  store volatile i32 0, ptr %local
  br i1 %choose, label %early, label %normal
early:
  %v = load volatile i32, ptr %local
  ret i32 %v
normal:
  call void @later()
  ret i32 7
}
