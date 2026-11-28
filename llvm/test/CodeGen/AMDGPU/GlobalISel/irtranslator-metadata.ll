; RUN: llc -global-isel -mtriple=amdgpu9.00 -stop-after=irtranslator %s -o %t.mir
; RUN: FileCheck %s < %t.mir
; RUN: llc -mtriple=amdgpu9.00 -run-pass=none %t.mir -o - | FileCheck %s

; The string node comes from IR. The translator wraps the integer operand in
; a new tuple. Both references must still identify their values after MIR I/O.
; CHECK: [[STR:![0-9]+]] = !{!"arst"}

define i32 @reloc_constant() {
  ; CHECK-LABEL: name: reloc_constant
  ; CHECK: machineMetadataNodes:
  ; CHECK-NEXT: - '[[CONST:![0-9]+]] = !{i32 4}'
  ; CHECK: bb.{{[0-9]+}} (%ir-block.0):
  ; CHECK-NEXT:   [[INT:%[0-9]+]]:_(i32) = G_INTRINSIC intrinsic(@llvm.amdgcn.reloc.constant), [[STR]]
  ; CHECK-NEXT:   [[INT1:%[0-9]+]]:_(i32) = G_INTRINSIC intrinsic(@llvm.amdgcn.reloc.constant), [[CONST]]
  ; CHECK-NEXT:   [[ADD:%[0-9]+]]:_(i32) = G_ADD [[INT]], [[INT1]]
  ; CHECK-NEXT:   $vgpr0 = COPY [[ADD]](i32)
  ; CHECK-NEXT:   SI_RETURN implicit $vgpr0
  %val0 = call i32 @llvm.amdgcn.reloc.constant(metadata !0)
  %val1 = call i32 @llvm.amdgcn.reloc.constant(metadata i32 4)
  %res = add i32 %val0, %val1
  ret i32 %res
}

declare i32 @llvm.amdgcn.reloc.constant(metadata) #0

attributes #0 = { nounwind readnone speculatable willreturn }

!0 = !{!"arst"}
