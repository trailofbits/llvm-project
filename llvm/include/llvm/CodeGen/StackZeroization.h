//===- StackZeroization.h - Stack clearing coverage -------------*- C++ -*-===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#ifndef LLVM_CODEGEN_STACKZEROIZATION_H
#define LLVM_CODEGEN_STACKZEROIZATION_H

#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/Support/Alignment.h"
#include "llvm/Support/Compiler.h"
#include "llvm/Support/Error.h"
#include <cstdint>

namespace llvm {

/// A fixed byte range [Offset, Offset + Size) in one stack address domain.
/// Offsets use a stable origin shared by all ranges with the same StackID:
/// entry SP for the default stack, and a target-defined origin for other
/// stacks. Offsets in different stack IDs cannot be compared or merged.
struct StackZeroizeRange {
  uint8_t StackID = 0;
  int64_t Offset = 0;
  uint64_t Size = 0;

  /// Guaranteed alignment of the address of the first byte, not of the origin
  /// or the range size. This does not permit rounding the range outwards.
  Align Alignment;
};

/// Complete coverage of the supplied owned static regions. An empty Ranges
/// vector is a successful result for a frame with no owned storage to clear.
struct StackZeroizeExtent {
  /// Nonempty, nonoverlapping ranges sorted by StackID and then Offset.
  /// Adjacent ranges within one stack domain are coalesced.
  SmallVector<StackZeroizeRange, 1> Ranges;
};

/// Compute whole-frame clearing coverage from finalized, target-supplied facts.
/// OwnedRegions must describe all storage the function owns at the clearing
/// point, including padding, saved-register slots, emergency spill slots, and
/// reserved outgoing-call space. RequiredObjects must describe every frame
/// object that needs clearing. Caller-owned storage belongs in neither list.
/// Ownership must not be inferred solely from a frame index's sign or from
/// MachineFrameInfo::getStackSize().
///
/// The caller must reject layouts it cannot describe completely with fixed
/// ranges, including unknown dynamic or scalable extents. A zero Size here
/// means a known empty range, not a variable-sized MachineFrameInfo object.
/// Saved values must be restored before their owned slots are actually erased;
/// calculating their extent neither establishes nor changes that ordering.
///
/// Return exactly the union of OwnedRegions, including bytes without an object,
/// after verifying that it contains every RequiredObject. No unowned gaps are
/// filled. Alignment comes from the supplied owned regions. Return an error,
/// with no partial extent, if a range's exclusive end cannot be represented as
/// an int64_t or a required object is not fully covered in its stack domain.
/// No metadata refinement, diagnostics, or machine instructions are emitted.
LLVM_ABI Expected<StackZeroizeExtent>
computeStackZeroizeExtent(ArrayRef<StackZeroizeRange> OwnedRegions,
                          ArrayRef<StackZeroizeRange> RequiredObjects);

} // namespace llvm

#endif // LLVM_CODEGEN_STACKZEROIZATION_H
