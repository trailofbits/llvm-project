//===- StackZeroizationTest.cpp --------------------------------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#include "llvm/CodeGen/StackZeroization.h"
#include "llvm/Testing/Support/Error.h"
#include "gtest/gtest.h"
#include <limits>

using namespace llvm;

namespace {

StackZeroizeRange range(int64_t Offset, uint64_t Size,
                        Align Alignment = Align(1), uint8_t StackID = 0) {
  return {StackID, Offset, Size, Alignment};
}

void expectRange(const StackZeroizeRange &Actual, int64_t Offset, uint64_t Size,
                 Align Alignment = Align(1), uint8_t StackID = 0) {
  EXPECT_EQ(Actual.StackID, StackID);
  EXPECT_EQ(Actual.Offset, Offset);
  EXPECT_EQ(Actual.Size, Size);
  EXPECT_EQ(Actual.Alignment, Alignment);
}

constexpr int64_t MinOffset = std::numeric_limits<int64_t>::min();
constexpr int64_t MaxOffset = std::numeric_limits<int64_t>::max();
constexpr uint64_t MaxSize = std::numeric_limits<uint64_t>::max();

TEST(StackZeroizationTest, EmptyFrame) {
  auto Extent = computeStackZeroizeExtent({}, {});
  ASSERT_THAT_EXPECTED(Extent, Succeeded());
  EXPECT_TRUE(Extent->Ranges.empty());
}

TEST(StackZeroizationTest, ObjectWithoutOwnedStorageFails) {
  auto Extent = computeStackZeroizeExtent({}, {range(-8, 8)});
  EXPECT_THAT_EXPECTED(
      Extent, FailedWithMessage("required stack range is not fully owned"));
}

TEST(StackZeroizationTest, WholeFrameIncludesPaddingAndUnlistedStorage) {
  // An owned allocation also covers outgoing-call space and padding that have
  // no frame objects. The objects represent a local, spills, and saved values.
  auto Extent = computeStackZeroizeExtent(
      {range(-96, 96, Align(16))},
      {range(-72, 24), range(-40, 8), range(-32, 8), range(-16, 16)});
  ASSERT_THAT_EXPECTED(Extent, Succeeded());
  ASSERT_EQ(Extent->Ranges.size(), 1u);
  expectRange(Extent->Ranges[0], -96, 96, Align(16));
}

TEST(StackZeroizationTest, OwnedStorageWithoutObjectsIsStillCleared) {
  auto Extent = computeStackZeroizeExtent({range(-32, 32, Align(16))}, {});
  ASSERT_THAT_EXPECTED(Extent, Succeeded());
  ASSERT_EQ(Extent->Ranges.size(), 1u);
  expectRange(Extent->Ranges[0], -32, 32, Align(16));
}

TEST(StackZeroizationTest, PreservesUnownedGaps) {
  auto Extent = computeStackZeroizeExtent({range(-32, 32), range(-64, 16)},
                                          {range(-64, 16), range(-32, 32)});
  ASSERT_THAT_EXPECTED(Extent, Succeeded());
  ASSERT_EQ(Extent->Ranges.size(), 2u);
  expectRange(Extent->Ranges[0], -64, 16);
  expectRange(Extent->Ranges[1], -32, 32);
}

TEST(StackZeroizationTest, ObjectCanSpanAdjacentOwnedRegions) {
  auto Extent = computeStackZeroizeExtent({range(-32, 32), range(-64, 32)},
                                          {range(-40, 16)});
  ASSERT_THAT_EXPECTED(Extent, Succeeded());
  ASSERT_EQ(Extent->Ranges.size(), 1u);
  expectRange(Extent->Ranges[0], -64, 64);
}

TEST(StackZeroizationTest, CoalescesOverlapsAndDuplicates) {
  auto Extent = computeStackZeroizeExtent(
      {range(-24, 24), range(-64, 32), range(-48, 32), range(-64, 32)},
      {range(-64, 64), range(-32, 8), range(-32, 8)});
  ASSERT_THAT_EXPECTED(Extent, Succeeded());
  ASSERT_EQ(Extent->Ranges.size(), 1u);
  expectRange(Extent->Ranges[0], -64, 64);
}

TEST(StackZeroizationTest, DoesNotRoundOutwards) {
  auto Extent = computeStackZeroizeExtent({range(-13, 12)}, {range(-12, 8)});
  ASSERT_THAT_EXPECTED(Extent, Succeeded());
  ASSERT_EQ(Extent->Ranges.size(), 1u);
  expectRange(Extent->Ranges[0], -13, 12);
}

TEST(StackZeroizationTest, MissingBytesAtEitherBoundaryFail) {
  // This includes caller-owned bytes at and above entry SP.
  for (auto Object :
       {range(-65, 1), range(-1, 2), range(0, 8), range(-64, 65)}) {
    SCOPED_TRACE(Object.Offset);
    auto Extent = computeStackZeroizeExtent({range(-64, 64)}, {Object});
    EXPECT_THAT_EXPECTED(
        Extent, FailedWithMessage("required stack range is not fully owned"));
  }
}

TEST(StackZeroizationTest, ObjectCannotCrossUnownedGap) {
  auto Extent = computeStackZeroizeExtent({range(-64, 16), range(-32, 32)},
                                          {range(-56, 32)});
  EXPECT_THAT_EXPECTED(
      Extent, FailedWithMessage("required stack range is not fully owned"));
}

TEST(StackZeroizationTest, SeparateStackDomainsStaySeparate) {
  auto Extent = computeStackZeroizeExtent(
      {range(-16, 16, Align(8), 1), range(-32, 16, Align(16)),
       range(-32, 16, Align(8), 1)},
      {range(-32, 32, Align(1), 1), range(-32, 16)});
  ASSERT_THAT_EXPECTED(Extent, Succeeded());
  ASSERT_EQ(Extent->Ranges.size(), 2u);
  expectRange(Extent->Ranges[0], -32, 16, Align(16));
  expectRange(Extent->Ranges[1], -32, 32, Align(8), 1);
}

TEST(StackZeroizationTest, DifferentStackCannotProvideCoverage) {
  auto Extent = computeStackZeroizeExtent({range(-32, 32)},
                                          {range(-32, 32, Align(1), 1)});
  EXPECT_THAT_EXPECTED(
      Extent, FailedWithMessage("required stack range is not fully owned"));
}

TEST(StackZeroizationTest, KnownEmptyRangesAreIgnored) {
  auto Extent = computeStackZeroizeExtent(
      {range(MinOffset, 0), range(MaxOffset, 0)}, {range(24, 0, Align(1), 1)});
  ASSERT_THAT_EXPECTED(Extent, Succeeded());
  EXPECT_TRUE(Extent->Ranges.empty());
}

TEST(StackZeroizationTest, InteriorAlignmentDoesNotStrengthenMergedStart) {
  auto Extent = computeStackZeroizeExtent(
      {range(-16, 16, Align(16)), range(-24, 16, Align(8))}, {});
  ASSERT_THAT_EXPECTED(Extent, Succeeded());
  ASSERT_EQ(Extent->Ranges.size(), 1u);
  expectRange(Extent->Ranges[0], -24, 24, Align(8));
}

TEST(StackZeroizationTest, InteriorAlignmentDoesNotWeakenMergedStart) {
  auto Extent = computeStackZeroizeExtent(
      {range(-32, 32, Align(16)), range(-28, 4, Align(4))}, {});
  ASSERT_THAT_EXPECTED(Extent, Succeeded());
  ASSERT_EQ(Extent->Ranges.size(), 1u);
  expectRange(Extent->Ranges[0], -32, 32, Align(16));
}

TEST(StackZeroizationTest, EqualStartsCombineAlignmentGuarantees) {
  auto Extent = computeStackZeroizeExtent(
      {range(-32, 32, Align(16)), range(-32, 16, Align(32))}, {});
  ASSERT_THAT_EXPECTED(Extent, Succeeded());
  ASSERT_EQ(Extent->Ranges.size(), 1u);
  expectRange(Extent->Ranges[0], -32, 32, Align(32));
}

TEST(StackZeroizationTest, OwnedRangeOverflowReturnsNoPartialExtent) {
  for (auto Owned : {range(MaxOffset, 1), range(0, uint64_t(MaxOffset) + 1),
                     range(-1, MaxSize)}) {
    auto Extent = computeStackZeroizeExtent({range(-64, 64), Owned}, {});
    EXPECT_THAT_EXPECTED(
        Extent,
        FailedWithMessage("stack range end overflows signed 64-bit offsets"));
  }
}

TEST(StackZeroizationTest, RequiredRangeOverflowFails) {
  auto Extent =
      computeStackZeroizeExtent({range(-64, 64)}, {range(MaxOffset, 1)});
  EXPECT_THAT_EXPECTED(
      Extent,
      FailedWithMessage("stack range end overflows signed 64-bit offsets"));
}

TEST(StackZeroizationTest, FullRepresentableSpan) {
  auto Extent =
      computeStackZeroizeExtent({range(MinOffset, MaxSize)},
                                {range(MinOffset, MaxSize),
                                 range(MaxOffset - 1, 1), range(MinOffset, 1)});
  ASSERT_THAT_EXPECTED(Extent, Succeeded());
  ASSERT_EQ(Extent->Ranges.size(), 1u);
  expectRange(Extent->Ranges[0], MinOffset, MaxSize);
}

TEST(StackZeroizationTest, MergedSizeMayExceedSignedMaximum) {
  auto Extent = computeStackZeroizeExtent(
      {range(MinOffset, uint64_t(MaxOffset) + 1), range(0, MaxOffset)},
      {range(MinOffset, MaxSize)});
  ASSERT_THAT_EXPECTED(Extent, Succeeded());
  ASSERT_EQ(Extent->Ranges.size(), 1u);
  expectRange(Extent->Ranges[0], MinOffset, MaxSize);
}

TEST(StackZeroizationTest, ExhaustiveSmallRanges) {
  // Check every pair of small owned ranges against a byte-by-byte oracle.
  // This covers both input orders, nesting, overlap, adjacency, and gaps.
  for (int A = -3; A <= 3; ++A)
    for (int AE = A; AE <= 3; ++AE)
      for (int B = -3; B <= 3; ++B)
        for (int BE = B; BE <= 3; ++BE) {
          SCOPED_TRACE(::testing::Message() << '[' << A << ',' << AE << ") ["
                                            << B << ',' << BE << ')');
          StackZeroizeRange Owned[] = {range(A, AE - A), range(B, BE - B)};
          auto IsOwned = [&](int Byte) {
            return (A <= Byte && Byte < AE) || (B <= Byte && Byte < BE);
          };
          auto Extent = computeStackZeroizeExtent(Owned, {});
          ASSERT_THAT_EXPECTED(Extent, Succeeded());
          for (int Byte = -4; Byte <= 4; ++Byte) {
            unsigned Count = 0;
            for (const auto &Range : Extent->Ranges)
              Count += Range.Offset <= Byte &&
                       Byte < Range.Offset + int64_t(Range.Size);
            EXPECT_EQ(Count, unsigned(IsOwned(Byte)));
          }
          for (int C = -3; C <= 3; ++C)
            for (int CE = C; CE <= 3; ++CE) {
              bool Covered = true;
              for (int Byte = C; Byte < CE; ++Byte)
                Covered &= IsOwned(Byte);
              auto Result =
                  computeStackZeroizeExtent(Owned, {range(C, CE - C)});
              if (Covered)
                EXPECT_THAT_EXPECTED(Result, Succeeded());
              else
                EXPECT_THAT_EXPECTED(Result, Failed());
            }
        }
}

} // namespace
