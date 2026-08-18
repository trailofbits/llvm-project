; A function carrying "zeroize-stack" clears its own frame before returning.
; Inlining dissolves that frame into the caller's, so the callee is inlined only
; into a caller that carries the attribute as well and whose mode clears at least
; as much of the frame. "used" is the widest mode and any unrecognized mode is
; treated as "used", so "sensitive" is the only mode that clears less: a "used"
; caller takes a callee of either mode, a "sensitive" caller takes only a
; "sensitive" callee, and an unannotated caller takes neither. A callee that does
; not carry the attribute is unconstrained by this. A request to inline does not
; override the rule.
;
; LangRef requires that an unrecognized mode not clear less than a recognized
; one. In each group of mode-value cases below, the refusal into a "sensitive"
; caller is the row that pins that direction; the other rows in the group pin
; that refusal as the widest-mode reading rather than as a blanket refusal of
; the value.

; RUN: opt < %s -passes=inline -S | FileCheck %s
; RUN: opt < %s -passes='default<O2>' -S | FileCheck %s --check-prefix=O2

;; Each refusal is checked against the reason the inliner reports for it, so a
;; refusal that fires for some unrelated cause, or inlining being switched off
;; altogether, fails the test instead of passing it. The implicit-check-not
;; makes the list exhaustive: an inline that stops being refused, or a refusal
;; that appears where none is expected, is a failure either way.
; RUN: opt < %s -passes=inline -pass-remarks-missed=inline -disable-output 2>&1 \
; RUN:   | FileCheck %s --check-prefix=REMARK --implicit-check-not="remark: "
;; Any function added below that produces a missed-inline remark has to add its
;; REMARK line as well, in source order.

declare void @sink(i32)

define void @zeroize_used_callee(i32 %x) "zeroize-stack"="used" {
  call void @sink(i32 %x)
  ret void
}

define void @zeroize_sensitive_callee(i32 %x) "zeroize-stack"="sensitive" {
  call void @sink(i32 %x)
  ret void
}

;; Not a mode this or any other version of the attribute defines. LangRef gives
;; any unrecognized value the meaning of "used", the widest mode, so this callee
;; promises a clear of its whole frame just as a "used" one does.

define void @zeroize_unrecognized_callee(i32 %x) "zeroize-stack"="not-a-real-mode" {
  call void @sink(i32 %x)
  ret void
}

;; An empty value is not a mode either, and neither is an absent one: an absent,
;; an empty, and an unrecognized value all mean "used", the widest mode. So a
;; value this consumer cannot interpret clears more of the frame than it must,
;; never less, and each of these callees promises a clear of its whole frame
;; just as a "used" one does.
;;
;; The two spellings are the same attribute once parsed. Attribute::getAsString
;; prints ="value" only for a non-empty value, so "zeroize-stack"="" prints as
;; the bare "zeroize-stack" and the two collapse into one attribute group: the
;; valueless form is what -S and bitcode emit, which is why it is covered here
;; and not only the spelling written below.

define void @zeroize_empty_callee(i32 %x) "zeroize-stack"="" {
  call void @sink(i32 %x)
  ret void
}

define void @zeroize_valueless_callee(i32 %x) "zeroize-stack" {
  call void @sink(i32 %x)
  ret void
}

define void @plain_callee(i32 %x) {
  call void @sink(i32 %x)
  ret void
}

define void @zeroize_alwaysinline_callee(i32 %x) alwaysinline "zeroize-stack"="used" {
  call void @sink(i32 %x)
  ret void
}

;; Refused into a caller with no attribute, in either mode: the caller clears
;; nothing, so the bytes the callee promised to clear would be left behind.

define void @unannotated_caller(i32 %x) {
; CHECK-LABEL: define void @unannotated_caller(
; CHECK: call void @zeroize_used_callee(
; CHECK: call void @zeroize_sensitive_callee(
; CHECK-NOT: call void @sink(
;
; O2-LABEL: define void @unannotated_caller(
; O2: call void @zeroize_used_callee(
; O2: call void @zeroize_sensitive_callee(
; O2-NOT: call void @sink(
;
; REMARK: remark: {{.*}} 'zeroize_used_callee' not inlined into 'unannotated_caller'{{.*}}: conflicting attributes
; REMARK: remark: {{.*}} 'zeroize_sensitive_callee' not inlined into 'unannotated_caller'{{.*}}: conflicting attributes
  call void @zeroize_used_callee(i32 %x)
  call void @zeroize_sensitive_callee(i32 %x)
  ret void
}

;; Inlined into an equally protected caller: "used" into "used" clears the whole
;; frame on both sides, so the callee's bytes end up in a frame that is cleared.

define void @used_into_used_caller(i32 %x) "zeroize-stack"="used" {
; CHECK-LABEL: define void @used_into_used_caller(
; CHECK-NOT: call void @zeroize_used_callee(
; CHECK: call void @sink(
;
; O2-LABEL: define void @used_into_used_caller(
; O2-NOT: call void @zeroize_used_callee(
; O2: call void @sink(
  call void @zeroize_used_callee(i32 %x)
  ret void
}

;; "sensitive" into "sensitive": the caller asks for exactly what the callee did.

define void @sensitive_into_sensitive_caller(i32 %x) "zeroize-stack"="sensitive" {
; CHECK-LABEL: define void @sensitive_into_sensitive_caller(
; CHECK-NOT: call void @zeroize_sensitive_callee(
; CHECK: call void @sink(
;
; O2-LABEL: define void @sensitive_into_sensitive_caller(
; O2-NOT: call void @zeroize_sensitive_callee(
; O2: call void @sink(
  call void @zeroize_sensitive_callee(i32 %x)
  ret void
}

;; "sensitive" into "used": the caller clears more than the callee asked for,
;; which keeps the callee's guarantee and then some.

define void @sensitive_into_used_caller(i32 %x) "zeroize-stack"="used" {
; CHECK-LABEL: define void @sensitive_into_used_caller(
; CHECK-NOT: call void @zeroize_sensitive_callee(
; CHECK: call void @sink(
;
; O2-LABEL: define void @sensitive_into_used_caller(
; O2-NOT: call void @zeroize_sensitive_callee(
; O2: call void @sink(
  call void @zeroize_sensitive_callee(i32 %x)
  ret void
}

;; "used" into "sensitive" is refused, and this is the one pair where both
;; functions are protected and inlining is still wrong: the caller may spare
;; slots traced back to objects marked nozeroize, so it does not necessarily
;; clear everything the callee undertook to clear.

define void @used_into_sensitive_caller(i32 %x) "zeroize-stack"="sensitive" {
; CHECK-LABEL: define void @used_into_sensitive_caller(
; CHECK: call void @zeroize_used_callee(
; CHECK-NOT: call void @sink(
;
; O2-LABEL: define void @used_into_sensitive_caller(
; O2: call void @zeroize_used_callee(
; O2-NOT: call void @sink(
;
; REMARK: remark: {{.*}} 'zeroize_used_callee' not inlined into 'used_into_sensitive_caller'{{.*}}: conflicting attributes
  call void @zeroize_used_callee(i32 %x)
  ret void
}

;; An unrecognized mode is treated as "used", the widest mode, and the direction
;; that matters is the one LangRef forbids: it must not be read as clearing the
;; least. This row is the one that pins that direction -- an unrecognized-mode
;; callee is refused into a "sensitive" caller, exactly as a "used" callee is.
;; An implementation that fell back to clearing the least, or that ignored a
;; mode it could not parse, would inline here. The two rows that follow do not
;; pin the direction; they pin this refusal as the widest-mode reading.

define void @unrecognized_into_sensitive_caller(i32 %x) "zeroize-stack"="sensitive" {
; CHECK-LABEL: define void @unrecognized_into_sensitive_caller(
; CHECK: call void @zeroize_unrecognized_callee(
; CHECK-NOT: call void @sink(
;
; O2-LABEL: define void @unrecognized_into_sensitive_caller(
; O2: call void @zeroize_unrecognized_callee(
; O2-NOT: call void @sink(
;
; REMARK: remark: {{.*}} 'zeroize_unrecognized_callee' not inlined into 'unrecognized_into_sensitive_caller'{{.*}}: conflicting attributes
  call void @zeroize_unrecognized_callee(i32 %x)
  ret void
}

;; The same reading in the permitted direction, so that the refusal above is
;; pinned as the widest-mode reading rather than as a blanket refusal of an
;; unrecognized value: an unrecognized-mode caller clears its whole frame, so it
;; takes a "sensitive" callee, which asked for less. A mode that could not be
;; parsed is not a reason to refuse.

define void @sensitive_into_unrecognized_caller(i32 %x) "zeroize-stack"="not-a-real-mode" {
; CHECK-LABEL: define void @sensitive_into_unrecognized_caller(
; CHECK-NOT: call void @zeroize_sensitive_callee(
; CHECK: call void @sink(
;
; O2-LABEL: define void @sensitive_into_unrecognized_caller(
; O2-NOT: call void @zeroize_sensitive_callee(
; O2: call void @sink(
  call void @zeroize_sensitive_callee(i32 %x)
  ret void
}

;; Two different unrecognized modes: both mean "used", so neither clears less
;; than the other and the inline goes through. Two unequal strings are not a
;; mismatch when both denote the widest mode.

define void @unrecognized_into_unrecognized_caller(i32 %x) "zeroize-stack"="also-not-a-real-mode" {
; CHECK-LABEL: define void @unrecognized_into_unrecognized_caller(
; CHECK-NOT: call void @zeroize_unrecognized_callee(
; CHECK: call void @sink(
;
; O2-LABEL: define void @unrecognized_into_unrecognized_caller(
; O2-NOT: call void @zeroize_unrecognized_callee(
; O2: call void @sink(
  call void @zeroize_unrecognized_callee(i32 %x)
  ret void
}

;; The empty value read as the widest mode, in the direction that costs an
;; inline, and this row is the one that pins it: an empty-valued callee is
;; refused into a "sensitive" caller, exactly as a "used" or an
;; unrecognized-mode one is, because the value is not "sensitive" and so
;; promises a clear of the whole frame that a "sensitive" caller does not
;; necessarily make. An implementation that read a value it could not interpret
;; as the narrowest mode, or that skipped the check when the value was empty,
;; would inline here.

define void @empty_into_sensitive_caller(i32 %x) "zeroize-stack"="sensitive" {
; CHECK-LABEL: define void @empty_into_sensitive_caller(
; CHECK: call void @zeroize_empty_callee(
; CHECK-NOT: call void @sink(
;
; O2-LABEL: define void @empty_into_sensitive_caller(
; O2: call void @zeroize_empty_callee(
; O2-NOT: call void @sink(
;
; REMARK: remark: {{.*}} 'zeroize_empty_callee' not inlined into 'empty_into_sensitive_caller'{{.*}}: conflicting attributes
  call void @zeroize_empty_callee(i32 %x)
  ret void
}

;; The same reading in the permitted direction, so that the refusal above is
;; pinned as the widest mode rather than as a blanket refusal of the empty
;; value: an empty-valued caller clears its whole frame, so it takes a
;; "sensitive" callee, which asked for less.

define void @sensitive_into_empty_caller(i32 %x) "zeroize-stack"="" {
; CHECK-LABEL: define void @sensitive_into_empty_caller(
; CHECK-NOT: call void @zeroize_sensitive_callee(
; CHECK: call void @sink(
;
; O2-LABEL: define void @sensitive_into_empty_caller(
; O2-NOT: call void @zeroize_sensitive_callee(
; O2: call void @sink(
  call void @zeroize_sensitive_callee(i32 %x)
  ret void
}

;; Empty into empty: both mean the widest mode, so neither clears less than the
;; other and the inline goes through. Two equal strings that are equally not a
;; mode are not a mismatch.

define void @empty_into_empty_caller(i32 %x) "zeroize-stack"="" {
; CHECK-LABEL: define void @empty_into_empty_caller(
; CHECK-NOT: call void @zeroize_empty_callee(
; CHECK: call void @sink(
;
; O2-LABEL: define void @empty_into_empty_caller(
; O2-NOT: call void @zeroize_empty_callee(
; O2: call void @sink(
  call void @zeroize_empty_callee(i32 %x)
  ret void
}

;; The valueless spelling, refused into a "sensitive" caller for the same
;; reason. This is the form the empty value prints and reloads as, so it is the
;; one a module reaching the inliner actually carries, and it has to be read as
;; the widest mode too.

define void @valueless_into_sensitive_caller(i32 %x) "zeroize-stack"="sensitive" {
; CHECK-LABEL: define void @valueless_into_sensitive_caller(
; CHECK: call void @zeroize_valueless_callee(
; CHECK-NOT: call void @sink(
;
; O2-LABEL: define void @valueless_into_sensitive_caller(
; O2: call void @zeroize_valueless_callee(
; O2-NOT: call void @sink(
;
; REMARK: remark: {{.*}} 'zeroize_valueless_callee' not inlined into 'valueless_into_sensitive_caller'{{.*}}: conflicting attributes
  call void @zeroize_valueless_callee(i32 %x)
  ret void
}

;; A callee without the attribute is still inlined into an annotated caller, and
;; that is the direction worth encouraging: the callee's frame sits below the
;; stack pointer at the caller's return and no clear reaches it, while inlining
;; turns those bytes into frame bytes the caller does clear.

define void @plain_into_used_caller(i32 %x) "zeroize-stack"="used" {
; CHECK-LABEL: define void @plain_into_used_caller(
; CHECK-NOT: call void @plain_callee(
; CHECK: call void @sink(
;
; O2-LABEL: define void @plain_into_used_caller(
; O2-NOT: call void @plain_callee(
; O2: call void @sink(
  call void @plain_callee(i32 %x)
  ret void
}

define void @plain_into_sensitive_caller(i32 %x) "zeroize-stack"="sensitive" {
; CHECK-LABEL: define void @plain_into_sensitive_caller(
; CHECK-NOT: call void @plain_callee(
; CHECK: call void @sink(
;
; O2-LABEL: define void @plain_into_sensitive_caller(
; O2-NOT: call void @plain_callee(
; O2: call void @sink(
  call void @plain_callee(i32 %x)
  ret void
}

;; A request to inline does not override the refusal, however it is spelled:
;; alwaysinline on the callee and on the call site both, into a caller that
;; clears nothing. The attribute compatibility check is bypassed on this path, so
;; this pins down that the rule is consulted there too.

define void @alwaysinline_caller(i32 %x) {
; CHECK-LABEL: define void @alwaysinline_caller(
; CHECK: call void @zeroize_alwaysinline_callee(
; CHECK-NOT: call void @sink(
;
; O2-LABEL: define void @alwaysinline_caller(
; O2: call void @zeroize_alwaysinline_callee(
; O2-NOT: call void @sink(
;
; REMARK: remark: {{.*}} 'zeroize_alwaysinline_callee' not inlined into 'alwaysinline_caller'{{.*}}: incompatible zeroize-stack attributes
  call void @zeroize_alwaysinline_callee(i32 %x) alwaysinline
  ret void
}

;; The same path in the permitted direction, so that the rule being consulted
;; there is pinned as a rule and not as a blanket refusal: the alwaysinline
;; callee goes into a caller whose mode clears at least as much, and the call
;; is gone. A check that only ever saw the refusal above would still pass if
;; this path refused everything.

define void @alwaysinline_used_caller(i32 %x) "zeroize-stack"="used" {
; CHECK-LABEL: define void @alwaysinline_used_caller(
; CHECK-NOT: call void @zeroize_alwaysinline_callee(
; CHECK: call void @sink(
;
; O2-LABEL: define void @alwaysinline_used_caller(
; O2-NOT: call void @zeroize_alwaysinline_callee(
; O2: call void @sink(
  call void @zeroize_alwaysinline_callee(i32 %x) alwaysinline
  ret void
}
