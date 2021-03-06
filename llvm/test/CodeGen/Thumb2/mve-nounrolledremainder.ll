; NOTE: Assertions have been autogenerated by utils/update_llc_test_checks.py
; RUN: llc -mtriple=thumbv8.1m.main-none-eabi -mattr=+mve.fp -o - %s | FileCheck --check-prefix=CHECK %s

define void @tailpred(half* nocapture readonly %pSrcA, half* nocapture readonly %pSrcB, half* nocapture %pDst, i32 %blockSize) {
; CHECK-LABEL: tailpred:
; CHECK:       @ %bb.0: @ %entry
; CHECK-NEXT:    .save {r4, r5, r7, lr}
; CHECK-NEXT:    push {r4, r5, r7, lr}
; CHECK-NEXT:    cmp r3, #0
; CHECK-NEXT:    beq .LBB0_6
; CHECK-NEXT:  @ %bb.1: @ %vector.memcheck
; CHECK-NEXT:    add.w r5, r2, r3, lsl #1
; CHECK-NEXT:    add.w r4, r1, r3, lsl #1
; CHECK-NEXT:    cmp r5, r1
; CHECK-NEXT:    cset r12, hi
; CHECK-NEXT:    cmp r4, r2
; CHECK-NEXT:    cset lr, hi
; CHECK-NEXT:    cmp r5, r0
; CHECK-NEXT:    add.w r5, r0, r3, lsl #1
; CHECK-NEXT:    cset r4, hi
; CHECK-NEXT:    cmp r5, r2
; CHECK-NEXT:    cset r5, hi
; CHECK-NEXT:    ands r4, r5
; CHECK-NEXT:    lsls r4, r4, #31
; CHECK-NEXT:    itt eq
; CHECK-NEXT:    andeq.w r5, lr, r12
; CHECK-NEXT:    lslseq.w r5, r5, #31
; CHECK-NEXT:    beq .LBB0_4
; CHECK-NEXT:  @ %bb.2: @ %while.body.preheader
; CHECK-NEXT:    dls lr, r3
; CHECK-NEXT:  .LBB0_3: @ %while.body
; CHECK-NEXT:    @ =>This Inner Loop Header: Depth=1
; CHECK-NEXT:    vldr.16 s0, [r0]
; CHECK-NEXT:    vldr.16 s2, [r1]
; CHECK-NEXT:    adds r1, #2
; CHECK-NEXT:    adds r0, #2
; CHECK-NEXT:    vadd.f16 s0, s2, s0
; CHECK-NEXT:    vstr.16 s0, [r2]
; CHECK-NEXT:    adds r2, #2
; CHECK-NEXT:    le lr, .LBB0_3
; CHECK-NEXT:    b .LBB0_6
; CHECK-NEXT:  .LBB0_4: @ %vector.ph
; CHECK-NEXT:    dlstp.16 lr, r3
; CHECK-NEXT:  .LBB0_5: @ %vector.body
; CHECK-NEXT:    @ =>This Inner Loop Header: Depth=1
; CHECK-NEXT:    vldrh.u16 q0, [r0], #16
; CHECK-NEXT:    vldrh.u16 q1, [r1], #16
; CHECK-NEXT:    vadd.f16 q0, q1, q0
; CHECK-NEXT:    vstrh.16 q0, [r2], #16
; CHECK-NEXT:    letp lr, .LBB0_5
; CHECK-NEXT:  .LBB0_6: @ %while.end
; CHECK-NEXT:    pop {r4, r5, r7, pc}
entry:
  %cmp.not6 = icmp eq i32 %blockSize, 0
  br i1 %cmp.not6, label %while.end, label %vector.memcheck

vector.memcheck:                                  ; preds = %entry
  %scevgep = getelementptr half, half* %pDst, i32 %blockSize
  %scevgep14 = getelementptr half, half* %pSrcA, i32 %blockSize
  %scevgep17 = getelementptr half, half* %pSrcB, i32 %blockSize
  %bound0 = icmp ugt half* %scevgep14, %pDst
  %bound1 = icmp ugt half* %scevgep, %pSrcA
  %found.conflict = and i1 %bound0, %bound1
  %bound019 = icmp ugt half* %scevgep17, %pDst
  %bound120 = icmp ugt half* %scevgep, %pSrcB
  %found.conflict21 = and i1 %bound019, %bound120
  %conflict.rdx = or i1 %found.conflict, %found.conflict21
  br i1 %conflict.rdx, label %while.body, label %vector.ph

vector.ph:                                        ; preds = %vector.memcheck
  %n.rnd.up = add i32 %blockSize, 7
  %n.vec = and i32 %n.rnd.up, -8
  br label %vector.body

vector.body:                                      ; preds = %vector.body, %vector.ph
  %index = phi i32 [ 0, %vector.ph ], [ %index.next, %vector.body ]
  %next.gep = getelementptr half, half* %pSrcA, i32 %index
  %next.gep28 = getelementptr half, half* %pDst, i32 %index
  %next.gep29 = getelementptr half, half* %pSrcB, i32 %index
  %active.lane.mask = call <8 x i1> @llvm.get.active.lane.mask.v8i1.i32(i32 %index, i32 %blockSize)
  %0 = bitcast half* %next.gep to <8 x half>*
  %wide.masked.load = call <8 x half> @llvm.masked.load.v8f16.p0v8f16(<8 x half>* %0, i32 2, <8 x i1> %active.lane.mask, <8 x half> undef)
  %1 = bitcast half* %next.gep29 to <8 x half>*
  %wide.masked.load32 = call <8 x half> @llvm.masked.load.v8f16.p0v8f16(<8 x half>* %1, i32 2, <8 x i1> %active.lane.mask, <8 x half> undef)
  %2 = fadd fast <8 x half> %wide.masked.load32, %wide.masked.load
  %3 = bitcast half* %next.gep28 to <8 x half>*
  call void @llvm.masked.store.v8f16.p0v8f16(<8 x half> %2, <8 x half>* %3, i32 2, <8 x i1> %active.lane.mask)
  %index.next = add i32 %index, 8
  %4 = icmp eq i32 %index.next, %n.vec
  br i1 %4, label %while.end, label %vector.body

while.body:                                       ; preds = %vector.memcheck, %while.body
  %blkCnt.010 = phi i32 [ %dec, %while.body ], [ %blockSize, %vector.memcheck ]
  %pSrcA.addr.09 = phi half* [ %incdec.ptr, %while.body ], [ %pSrcA, %vector.memcheck ]
  %pDst.addr.08 = phi half* [ %incdec.ptr3, %while.body ], [ %pDst, %vector.memcheck ]
  %pSrcB.addr.07 = phi half* [ %incdec.ptr1, %while.body ], [ %pSrcB, %vector.memcheck ]
  %incdec.ptr = getelementptr inbounds half, half* %pSrcA.addr.09, i32 1
  %5 = load half, half* %pSrcA.addr.09, align 2
  %incdec.ptr1 = getelementptr inbounds half, half* %pSrcB.addr.07, i32 1
  %6 = load half, half* %pSrcB.addr.07, align 2
  %7 = fadd fast half %6, %5
  %incdec.ptr3 = getelementptr inbounds half, half* %pDst.addr.08, i32 1
  store half %7, half* %pDst.addr.08, align 2
  %dec = add i32 %blkCnt.010, -1
  %cmp.not = icmp eq i32 %dec, 0
  br i1 %cmp.not, label %while.end, label %while.body

while.end:                                        ; preds = %vector.body, %while.body, %entry
  ret void
}

define void @notailpred(half* nocapture readonly %pSrcA, half* nocapture readonly %pSrcB, half* nocapture %pDst, i32 %blockSize) {
; CHECK-LABEL: notailpred:
; CHECK:       @ %bb.0: @ %entry
; CHECK-NEXT:    .save {r4, r5, r6, r7, lr}
; CHECK-NEXT:    push {r4, r5, r6, r7, lr}
; CHECK-NEXT:    cbz r3, .LBB1_6
; CHECK-NEXT:  @ %bb.1: @ %while.body.preheader
; CHECK-NEXT:    cmp r3, #8
; CHECK-NEXT:    blo .LBB1_3
; CHECK-NEXT:  @ %bb.2: @ %vector.memcheck
; CHECK-NEXT:    add.w r5, r2, r3, lsl #1
; CHECK-NEXT:    add.w r6, r1, r3, lsl #1
; CHECK-NEXT:    cmp r5, r1
; CHECK-NEXT:    add.w r4, r0, r3, lsl #1
; CHECK-NEXT:    cset r7, hi
; CHECK-NEXT:    cmp r6, r2
; CHECK-NEXT:    cset r6, hi
; CHECK-NEXT:    cmp r5, r0
; CHECK-NEXT:    cset r5, hi
; CHECK-NEXT:    cmp r4, r2
; CHECK-NEXT:    cset r4, hi
; CHECK-NEXT:    ands r5, r4
; CHECK-NEXT:    lsls r5, r5, #31
; CHECK-NEXT:    itt eq
; CHECK-NEXT:    andeq r7, r6
; CHECK-NEXT:    lslseq.w r7, r7, #31
; CHECK-NEXT:    beq .LBB1_7
; CHECK-NEXT:  .LBB1_3:
; CHECK-NEXT:    mov r5, r3
; CHECK-NEXT:    mov r12, r0
; CHECK-NEXT:    mov r7, r2
; CHECK-NEXT:    mov r4, r1
; CHECK-NEXT:  .LBB1_4: @ %while.body.preheader31
; CHECK-NEXT:    dls lr, r5
; CHECK-NEXT:  .LBB1_5: @ %while.body
; CHECK-NEXT:    @ =>This Inner Loop Header: Depth=1
; CHECK-NEXT:    vldr.16 s0, [r12]
; CHECK-NEXT:    vldr.16 s2, [r4]
; CHECK-NEXT:    adds r4, #2
; CHECK-NEXT:    add.w r12, r12, #2
; CHECK-NEXT:    vadd.f16 s0, s2, s0
; CHECK-NEXT:    vstr.16 s0, [r7]
; CHECK-NEXT:    adds r7, #2
; CHECK-NEXT:    le lr, .LBB1_5
; CHECK-NEXT:  .LBB1_6: @ %while.end
; CHECK-NEXT:    pop {r4, r5, r6, r7, pc}
; CHECK-NEXT:  .LBB1_7: @ %vector.ph
; CHECK-NEXT:    bic r6, r3, #7
; CHECK-NEXT:    movs r5, #1
; CHECK-NEXT:    sub.w r7, r6, #8
; CHECK-NEXT:    add.w r4, r1, r6, lsl #1
; CHECK-NEXT:    add.w r12, r0, r6, lsl #1
; CHECK-NEXT:    add.w lr, r5, r7, lsr #3
; CHECK-NEXT:    add.w r7, r2, r6, lsl #1
; CHECK-NEXT:    dls lr, lr
; CHECK-NEXT:    and r5, r3, #7
; CHECK-NEXT:  .LBB1_8: @ %vector.body
; CHECK-NEXT:    @ =>This Inner Loop Header: Depth=1
; CHECK-NEXT:    vldrh.u16 q0, [r0], #16
; CHECK-NEXT:    vldrh.u16 q1, [r1], #16
; CHECK-NEXT:    vadd.f16 q0, q1, q0
; CHECK-NEXT:    vstrb.8 q0, [r2], #16
; CHECK-NEXT:    le lr, .LBB1_8
; CHECK-NEXT:  @ %bb.9: @ %middle.block
; CHECK-NEXT:    cmp r6, r3
; CHECK-NEXT:    bne .LBB1_4
; CHECK-NEXT:    b .LBB1_6
entry:
  %cmp.not6 = icmp eq i32 %blockSize, 0
  br i1 %cmp.not6, label %while.end, label %while.body.preheader

while.body.preheader:                             ; preds = %entry
  %min.iters.check = icmp ult i32 %blockSize, 8
  br i1 %min.iters.check, label %while.body.preheader31, label %vector.memcheck

vector.memcheck:                                  ; preds = %while.body.preheader
  %scevgep = getelementptr half, half* %pDst, i32 %blockSize
  %scevgep14 = getelementptr half, half* %pSrcA, i32 %blockSize
  %scevgep17 = getelementptr half, half* %pSrcB, i32 %blockSize
  %bound0 = icmp ugt half* %scevgep14, %pDst
  %bound1 = icmp ugt half* %scevgep, %pSrcA
  %found.conflict = and i1 %bound0, %bound1
  %bound019 = icmp ugt half* %scevgep17, %pDst
  %bound120 = icmp ugt half* %scevgep, %pSrcB
  %found.conflict21 = and i1 %bound019, %bound120
  %conflict.rdx = or i1 %found.conflict, %found.conflict21
  br i1 %conflict.rdx, label %while.body.preheader31, label %vector.ph

vector.ph:                                        ; preds = %vector.memcheck
  %n.vec = and i32 %blockSize, -8
  %ind.end = and i32 %blockSize, 7
  %ind.end23 = getelementptr half, half* %pSrcA, i32 %n.vec
  %ind.end25 = getelementptr half, half* %pDst, i32 %n.vec
  %ind.end27 = getelementptr half, half* %pSrcB, i32 %n.vec
  br label %vector.body

vector.body:                                      ; preds = %vector.body, %vector.ph
  %index = phi i32 [ 0, %vector.ph ], [ %index.next, %vector.body ]
  %next.gep = getelementptr half, half* %pSrcA, i32 %index
  %next.gep28 = getelementptr half, half* %pDst, i32 %index
  %next.gep29 = getelementptr half, half* %pSrcB, i32 %index
  %0 = bitcast half* %next.gep to <8 x half>*
  %wide.load = load <8 x half>, <8 x half>* %0, align 2
  %1 = bitcast half* %next.gep29 to <8 x half>*
  %wide.load30 = load <8 x half>, <8 x half>* %1, align 2
  %2 = fadd fast <8 x half> %wide.load30, %wide.load
  %3 = bitcast half* %next.gep28 to <8 x half>*
  store <8 x half> %2, <8 x half>* %3, align 2
  %index.next = add i32 %index, 8
  %4 = icmp eq i32 %index.next, %n.vec
  br i1 %4, label %middle.block, label %vector.body

middle.block:                                     ; preds = %vector.body
  %cmp.n = icmp eq i32 %n.vec, %blockSize
  br i1 %cmp.n, label %while.end, label %while.body.preheader31

while.body.preheader31:                           ; preds = %middle.block, %vector.memcheck, %while.body.preheader
  %blkCnt.010.ph = phi i32 [ %blockSize, %vector.memcheck ], [ %blockSize, %while.body.preheader ], [ %ind.end, %middle.block ]
  %pSrcA.addr.09.ph = phi half* [ %pSrcA, %vector.memcheck ], [ %pSrcA, %while.body.preheader ], [ %ind.end23, %middle.block ]
  %pDst.addr.08.ph = phi half* [ %pDst, %vector.memcheck ], [ %pDst, %while.body.preheader ], [ %ind.end25, %middle.block ]
  %pSrcB.addr.07.ph = phi half* [ %pSrcB, %vector.memcheck ], [ %pSrcB, %while.body.preheader ], [ %ind.end27, %middle.block ]
  br label %while.body

while.body:                                       ; preds = %while.body.preheader31, %while.body
  %blkCnt.010 = phi i32 [ %dec, %while.body ], [ %blkCnt.010.ph, %while.body.preheader31 ]
  %pSrcA.addr.09 = phi half* [ %incdec.ptr, %while.body ], [ %pSrcA.addr.09.ph, %while.body.preheader31 ]
  %pDst.addr.08 = phi half* [ %incdec.ptr3, %while.body ], [ %pDst.addr.08.ph, %while.body.preheader31 ]
  %pSrcB.addr.07 = phi half* [ %incdec.ptr1, %while.body ], [ %pSrcB.addr.07.ph, %while.body.preheader31 ]
  %incdec.ptr = getelementptr inbounds half, half* %pSrcA.addr.09, i32 1
  %5 = load half, half* %pSrcA.addr.09, align 2
  %incdec.ptr1 = getelementptr inbounds half, half* %pSrcB.addr.07, i32 1
  %6 = load half, half* %pSrcB.addr.07, align 2
  %7 = fadd fast half %6, %5
  %incdec.ptr3 = getelementptr inbounds half, half* %pDst.addr.08, i32 1
  store half %7, half* %pDst.addr.08, align 2
  %dec = add i32 %blkCnt.010, -1
  %cmp.not = icmp eq i32 %dec, 0
  br i1 %cmp.not, label %while.end, label %while.body

while.end:                                        ; preds = %while.body, %middle.block, %entry
  ret void
}

declare <8 x i1> @llvm.get.active.lane.mask.v8i1.i32(i32, i32) #1
declare <8 x half> @llvm.masked.load.v8f16.p0v8f16(<8 x half>*, i32 immarg, <8 x i1>, <8 x half>) #2
declare void @llvm.masked.store.v8f16.p0v8f16(<8 x half>, <8 x half>*, i32 immarg, <8 x i1>) #3
