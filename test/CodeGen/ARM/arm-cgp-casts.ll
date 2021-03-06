; RUN: llc -mtriple=thumbv8.main -mcpu=cortex-m33 %s -arm-disable-cgp=false -o - | FileCheck %s --check-prefix=CHECK-COMMON --check-prefix=CHECK-NODSP
; RUN: llc -mtriple=thumbv7-linux-android %s -arm-disable-cgp=false -o - | FileCheck %s --check-prefix=CHECK-COMMON --check-prefix=CHECK-NODSP
; RUN: llc -mtriple=thumbv7em %s -arm-disable-cgp=false -arm-enable-scalar-dsp=true -o - | FileCheck %s --check-prefix=CHECK-COMMON --check-prefix=CHECK-DSP
; RUN: llc -mtriple=thumbv8 %s -arm-disable-cgp=false -arm-enable-scalar-dsp=true -arm-enable-scalar-dsp-imms=true -o - | FileCheck %s --check-prefix=CHECK-COMMON --check-prefix=CHECK-DSP-IMM

; Transform will fail because the trunc is not a sink.
; CHECK-COMMON-LABEL: dsp_trunc
; CHECK-COMMON:   add   [[ADD:[^ ]+]],
; CHECK-DSP-NEXT: ldrh  r1, [r3]
; CHECK-DSP-NEXT: ldrh  r2, [r2]
; CHECK-DSP-NEXT: subs  r1, r1, [[ADD]]
; CHECK-DSP-NEXT: add   r0, r2
; CHECK-DSP-NEXT: uxth  r3, r1
; CHECK-DSP-NEXT: uxth  r2, r0
; CHECK-DSP-NEXT: cmp   r2, r3

; With DSP-IMM, we could have:
; movs  r1, #0
; uxth  r0, r0
; usub16  r1, r1, r0
; ldrh  r0, [r2]
; ldrh  r3, [r3]
; usub16  r0, r0, r1
; uadd16  r1, r3, r1
; cmp r0, r1
define i16 @dsp_trunc(i32 %arg0, i32 %arg1, i16* %gep0, i16* %gep1) {
entry:
  %add0 = add i32 %arg0, %arg1
  %conv0 = trunc i32 %add0 to i16
  %sub0 = sub i16 0, %conv0
  %load0 = load i16, i16* %gep0, align 2
  %load1 = load i16, i16* %gep1, align 2
  %sub1 = sub i16 %load0, %sub0
  %add1 = add i16 %load1, %sub0
  %cmp = icmp ult i16 %sub1, %add1
  %res = select i1 %cmp, i16 %add1, i16 %sub1
  ret i16 %res
}

; CHECK-COMMON-LABEL: trunc_i16_i8
; CHECK-COMMON: ldrh
; CHECK-COMMON: uxtb
; CHECK-COMMON: cmp
define i8 @trunc_i16_i8(i16* %ptr, i16 zeroext %arg0, i8 zeroext %arg1) {
entry:
  %0 = load i16, i16* %ptr
  %1 = add i16 %0, %arg0
  %2 = trunc i16 %1 to i8
  %3 = icmp ugt i8 %2, %arg1
  %4 = select i1 %3, i8 %2, i8 %arg1
  ret i8 %4
}

; The pass perform the transform, but a uxtb will still be inserted to handle
; the zext to the icmp.
; CHECK-COMMON-LABEL: icmp_i32_zext:
; CHECK-COMMON: sub
; CHECK-COMMON: uxtb
; CHECK-COMMON: cmp
define i8 @icmp_i32_zext(i8* %ptr) {
entry:
  %gep = getelementptr inbounds i8, i8* %ptr, i32 0
  %0 = load i8, i8* %gep, align 1
  %1 = sub nuw nsw i8 %0, 1
  %conv44 = zext i8 %0 to i32
  br label %preheader

preheader:
  br label %body

body:
  %2 = phi i8 [ %1, %preheader ], [ %3, %if.end ]
  %si.0274 = phi i32 [ %conv44, %preheader ], [ %inc, %if.end ]
  %conv51266 = zext i8 %2 to i32
  %cmp52267 = icmp eq i32 %si.0274, %conv51266
  br i1 %cmp52267, label %if.end, label %exit

if.end:
  %inc = add i32 %si.0274, 1
  %gep1 = getelementptr inbounds i8, i8* %ptr, i32 %inc
  %3 = load i8, i8* %gep1, align 1
  br label %body

exit:
  ret i8 %2
}

; Won't don't handle sext
; CHECK-COMMON-LABEL: icmp_sext_zext_store_i8_i16
; CHECK-COMMON: ldrb
; CHECK-COMMON: ldrsh
define i32 @icmp_sext_zext_store_i8_i16() {
entry:
  %0 = load i8, i8* getelementptr inbounds ([16 x i8], [16 x i8]* @d_uch, i32 0, i32 2), align 1
  %conv = zext i8 %0 to i16
  store i16 %conv, i16* @sh1, align 2
  %conv1 = zext i8 %0 to i32
  %1 = load i16, i16* getelementptr inbounds ([16 x i16], [16 x i16]* @d_sh, i32 0, i32 2), align 2
  %conv2 = sext i16 %1 to i32
  %cmp = icmp eq i32 %conv1, %conv2
  %conv3 = zext i1 %cmp to i32
  ret i32 %conv3
}

; CHECK-COMMON-LABEL: or_icmp_ugt:
; CHECK-COMMON:     ldrb
; CHECK-COMMON:     sub.w
; CHECK-COMMON-NOT: uxt
; CHECK-COMMON:     cmp.w
; CHECK-COMMON-NOT: uxt
; CHECK-COMMON:     cmp
define i1 @or_icmp_ugt(i32 %arg, i8* %ptr) {
entry:
  %0 = load i8, i8* %ptr
  %1 = zext i8 %0 to i32
  %mul = shl nuw nsw i32 %1, 1
  %add0 = add nuw nsw i32 %mul, 6
  %cmp0 = icmp ne i32 %arg, %add0
  %add1 = add i8 %0, -1
  %cmp1 = icmp ugt i8 %add1, 3
  %or = or i1 %cmp0, %cmp1
  ret i1 %or
}

; CHECK-COMMON-LABEL: icmp_switch_trunc:
; CHECK-COMMON-NOT: uxt
define i16 @icmp_switch_trunc(i16 zeroext %arg) {
entry:
  %conv = add nuw i16 %arg, 15
  %mul = mul nuw nsw i16 %conv, 3
  %trunc = trunc i16 %arg to i3
  switch i3 %trunc, label %default [
    i3 0, label %sw.bb
    i3 1, label %sw.bb.i
  ]

sw.bb:
  %cmp0 = icmp ult i16 %mul, 127
  %select = select i1 %cmp0, i16 %mul, i16 127
  br label %exit

sw.bb.i:
  %cmp1 = icmp ugt i16 %mul, 34
  %select.i = select i1 %cmp1, i16 %mul, i16 34
  br label %exit

default:
  br label %exit

exit:
  %res = phi i16 [ %select, %sw.bb ], [ %select.i, %sw.bb.i ], [ %mul, %default ]
  ret i16 %res
}

; We currently only handle truncs as sinks, so a uxt will still be needed for
; the icmp ugt instruction.
; CHECK-COMMON-LABEL: urem_trunc_icmps
; CHECK-COMMON: cmp
; CHECK-COMMON: uxt
; CHECK-COMMON: cmp
define void @urem_trunc_icmps(i16** %in, i32* %g, i32* %k) {
entry:
  %ptr = load i16*, i16** %in, align 4
  %ld = load i16, i16* %ptr, align 2
  %cmp.i = icmp eq i16 %ld, 0
  br i1 %cmp.i, label %exit, label %cond.false.i

cond.false.i:
  %rem = urem i16 5, %ld
  %extract.t = trunc i16 %rem to i8
  br label %body

body:
  %cond.in.i.off0 = phi i8 [ %extract.t, %cond.false.i ], [ %add, %for.inc ]
  %cmp = icmp ugt i8 %cond.in.i.off0, 7
  %conv5 = zext i1 %cmp to i32
  store i32 %conv5, i32* %g, align 4
  %.pr = load i32, i32* %k, align 4
  %tobool13150 = icmp eq i32 %.pr, 0
  br i1 %tobool13150, label %for.inc, label %exit

for.inc:
  %add = add nuw i8 %cond.in.i.off0, 1
  br label %body

exit:
  ret void
}

; CHECK-COMMON-LABEL: phi_feeding_switch
; CHECK-COMMON: ldrb
; CHECK-COMMON: uxtb
define void @phi_feeding_switch(i8* %memblock, i8* %store, i16 %arg) {
entry:
  %pre = load i8, i8* %memblock, align 1
  %conv = trunc i16 %arg to i8
  br label %header

header:
  %phi.0 = phi i8 [ %pre, %entry ], [ %count, %latch ]
  %phi.1 = phi i8 [ %conv, %entry ], [ %phi.3, %latch ]
  %phi.2 = phi i8 [ 0, %entry], [ %count, %latch ]
  switch i8 %phi.0, label %default [
    i8 43, label %for.inc.i
    i8 45, label %for.inc.i.i
  ]

for.inc.i:
  %xor = xor i8 %phi.1, 1
  br label %latch

for.inc.i.i:
  %and = and i8 %phi.1, 3
  br label %latch

default:
  %sub = sub i8 %phi.0, 1
  %cmp2 = icmp ugt i8 %sub, 4
  br i1 %cmp2, label %latch, label %exit

latch:
  %phi.3 = phi i8 [ %xor, %for.inc.i ], [ %and, %for.inc.i.i ], [ %phi.2, %default ]
  %count = add nuw i8 %phi.2, 1
  store i8 %count, i8* %store, align 1
  br label %header

exit:
  ret void
}

; Check that %exp requires uxth in all cases, and will also be required to
; promote %1 for the call - unless we can generate a uadd16.
; CHECK-COMMON-LABEL: zext_load_sink_call:
; CHECK-COMMON: uxt
; uadd16
; cmp
; CHECK-COMMON: uxt
define i32 @zext_load_sink_call(i16* %ptr, i16 %exp) {
entry:
  %0 = load i16, i16* %ptr, align 4
  %1 = add i16 %exp, 3
  %cmp = icmp eq i16 %0, %exp
  br i1 %cmp, label %exit, label %if.then

if.then:
  %conv0 = zext i16 %0 to i32
  %conv1 = zext i16 %1 to i32
  %call = tail call arm_aapcs_vfpcc i32 @dummy(i32 %conv0, i32 %conv1)
  br label %exit

exit:
  %exitval = phi i32 [ %call, %if.then ], [ 0, %entry  ]
  ret i32 %exitval
}

%class.ae = type { i8 }
%class.x = type { i8 }
%class.v = type { %class.q }
%class.q = type { i16 }

; CHECK-COMMON-LABEL: trunc_i16_i9_switch
; CHECK-COMMON-NOT: uxt
define i32 @trunc_i16_i9_switch(%class.ae* %this) {
entry:
  %call = tail call %class.x* @_ZNK2ae2afEv(%class.ae* %this)
  %call2 = tail call %class.v* @_ZN1x2acEv(%class.x* %call)
  %0 = getelementptr inbounds %class.v, %class.v* %call2, i32 0, i32 0, i32 0
  %1 = load i16, i16* %0, align 2
  %2 = trunc i16 %1 to i9
  %trunc = and i9 %2, -64
  switch i9 %trunc, label %cleanup.fold.split [
    i9 0, label %cleanup
    i9 -256, label %if.then7
  ]

if.then7:
  %3 = and i16 %1, 7
  %tobool = icmp eq i16 %3, 0
  %cond = select i1 %tobool, i32 2, i32 1
  br label %cleanup

cleanup.fold.split:
  br label %cleanup

cleanup:
  %retval.0 = phi i32 [ %cond, %if.then7 ], [ 0, %entry ], [ 2, %cleanup.fold.split ]
  ret i32 %retval.0
}

; CHECK-COMMON-LABEL: bitcast_i16
; CHECK-COMMON-NOT: uxt
define i16 @bitcast_i16(i16 zeroext %arg0, i16 zeroext %arg1) {
entry:
  %cast = bitcast i16 12345 to i16
  %add = add nuw i16 %arg0, 1
  %cmp = icmp ule i16 %add, %cast
  %res = select i1 %cmp, i16 %arg1, i16 32657
  ret i16 %res
}

; CHECK-COMMON-LABEL: bitcast_i8
; CHECK-COMMON-NOT: uxt
define i8 @bitcast_i8(i8 zeroext %arg0, i8 zeroext %arg1) {
entry:
  %cast = bitcast i8 127 to i8
  %mul = shl nuw i8 %arg0, 1
  %cmp = icmp uge i8 %mul, %arg1
  %res = select i1 %cmp, i8 %cast, i8 128
  ret i8 %res
}

; CHECK-COMMON-LABEL: bitcast_i16_minus
; CHECK-COMMON-NOT: uxt
define i16 @bitcast_i16_minus(i16 zeroext %arg0, i16 zeroext %arg1) {
entry:
  %cast = bitcast i16 -12345 to i16
  %xor = xor i16 %arg0, 7
  %cmp = icmp eq i16 %xor, %arg1
  %res = select i1 %cmp, i16 %cast, i16 32657
  ret i16 %res
}

; CHECK-COMMON-LABEL: bitcast_i8_minus
; CHECK-COMMON-NOT: uxt
define i8 @bitcast_i8_minus(i8 zeroext %arg0, i8 zeroext %arg1) {
entry:
  %cast = bitcast i8 -127 to i8
  %and = and i8 %arg0, 3
  %cmp = icmp ne i8 %and, %arg1
  %res = select i1 %cmp, i8 %cast, i8 128
  ret i8 %res
}

declare %class.x* @_ZNK2ae2afEv(%class.ae*) local_unnamed_addr
declare %class.v* @_ZN1x2acEv(%class.x*) local_unnamed_addr
declare i32 @dummy(i32, i32)

@d_uch = hidden local_unnamed_addr global [16 x i8] zeroinitializer, align 1
@sh1 = hidden local_unnamed_addr global i16 0, align 2
@d_sh = hidden local_unnamed_addr global [16 x i16] zeroinitializer, align 2
