//===- StackZeroization.cpp ------------------------------------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#include "llvm/CodeGen/StackZeroization.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/bit.h"
#include <algorithm>
#include <iterator>
#include <limits>
#include <tuple>

using namespace llvm;

static Expected<int64_t> getRangeEnd(const StackZeroizeRange &Range) {
  // Unsigned subtraction also represents the distance from a negative offset
  // to INT64_MAX, including distances larger than INT64_MAX itself.
  uint64_t MaxSize =
      uint64_t(std::numeric_limits<int64_t>::max()) - uint64_t(Range.Offset);
  if (Range.Size > MaxSize)
    return createStringError("stack range end overflows signed 64-bit offsets");

  // The bound check proves the mathematical sum fits in int64_t. Add in the
  // unsigned domain to avoid signed overflow or narrowing an unsigned size,
  // then reinterpret the two's-complement result without an out-of-range cast.
  return bit_cast<int64_t>(uint64_t(Range.Offset) + Range.Size);
}

static bool rangeLess(const StackZeroizeRange &LHS,
                      const StackZeroizeRange &RHS) {
  return std::tie(LHS.StackID, LHS.Offset) < std::tie(RHS.StackID, RHS.Offset);
}

Expected<StackZeroizeExtent>
llvm::computeStackZeroizeExtent(ArrayRef<StackZeroizeRange> OwnedRegions,
                                ArrayRef<StackZeroizeRange> RequiredObjects) {
  SmallVector<StackZeroizeRange> Sorted(OwnedRegions);
  llvm::sort(Sorted, rangeLess);

  StackZeroizeExtent Extent;
  int64_t LastEnd = 0;
  for (const StackZeroizeRange &Range : Sorted) {
    Expected<int64_t> End = getRangeEnd(Range);
    if (!End)
      return End.takeError();
    if (!Range.Size)
      continue;

    if (Extent.Ranges.empty() ||
        Extent.Ranges.back().StackID != Range.StackID ||
        Range.Offset > LastEnd) {
      Extent.Ranges.push_back(Range);
      LastEnd = *End;
      continue;
    }

    StackZeroizeRange &Last = Extent.Ranges.back();
    // Combine alignment guarantees only at identical starts.
    // An interior range may start at a more aligned address than Last does.
    if (Last.Offset == Range.Offset)
      Last.Alignment = std::max(Last.Alignment, Range.Alignment);
    LastEnd = std::max(LastEnd, *End);
    // The distance between two int64_t offsets fits in uint64_t, even when
    // the corresponding signed subtraction would overflow.
    Last.Size = uint64_t(LastEnd) - uint64_t(Last.Offset);
  }

  for (const StackZeroizeRange &Object : RequiredObjects) {
    Expected<int64_t> End = getRangeEnd(Object);
    if (!End)
      return End.takeError();
    if (!Object.Size)
      continue;

    auto Next = llvm::upper_bound(Extent.Ranges, Object, rangeLess);
    if (Next != Extent.Ranges.begin()) {
      const StackZeroizeRange &Owned = *std::prev(Next);
      if (Owned.StackID == Object.StackID && Owned.Offset <= Object.Offset) {
        uint64_t Displacement =
            uint64_t(Object.Offset) - uint64_t(Owned.Offset);
        if (Displacement <= Owned.Size &&
            Object.Size <= Owned.Size - Displacement)
          continue;
      }
    }

    return createStringError("required stack range is not fully owned");
  }

  return Extent;
}
