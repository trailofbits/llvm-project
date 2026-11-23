// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#include "probe.h"
#include <stddef.h>
#include <stdio.h>
#include <string.h>

const volatile unsigned char *ces_buffer_address;

_Static_assert(sizeof(unsigned long long) == 8, "probe needs 64-bit words");
_Static_assert(offsetof(struct ces_snapshot, flags) == 72, "flags offset");
_Static_assert(offsetof(struct ces_snapshot, xmm) == 80, "XMM offset");
_Static_assert(offsetof(struct ces_snapshot, buffer) == 336, "buffer offset");
_Static_assert(offsetof(struct ces_snapshot, preserved) == 400, "CSR offset");
_Static_assert(sizeof(struct ces_snapshot) == 424, "snapshot size");

static int bytes_equal(const unsigned char *bytes, size_t size,
                       unsigned char value) {
  for (size_t i = 0; i < size; ++i)
    if (bytes[i] != value)
      return 0;
  return 1;
}

static int preserved(const struct ces_snapshot *snapshot) {
  return snapshot->preserved[0] == 1 && snapshot->preserved[1] == 2 &&
         snapshot->preserved[2] == 3;
}

static int cleared(const struct ces_snapshot *snapshot) {
  const unsigned long long arithmetic_flags = 0x8d5;
  return preserved(snapshot) &&
         bytes_equal((const unsigned char *)snapshot->gpr,
                     sizeof(snapshot->gpr), 0) &&
         bytes_equal((const unsigned char *)snapshot->xmm,
                     sizeof(snapshot->xmm), 0) &&
         bytes_equal(snapshot->buffer, sizeof(snapshot->buffer), 0) &&
         (snapshot->flags & arithmetic_flags) == 0;
}

static int self_test(void) {
  struct ces_snapshot clean;
  struct ces_snapshot dirty;
  ces_probe(ces_zero_fixture, &clean);
  ces_probe(ces_unprotected, &dirty);
  if (!cleared(&clean)) {
    fputs("positive probe control failed\n", stderr);
    return 1;
  }
  if (!preserved(&dirty) ||
      !bytes_equal(dirty.buffer, sizeof(dirty.buffer), 0xa5) ||
      bytes_equal((const unsigned char *)dirty.xmm, sizeof(dirty.xmm), 0)) {
    fputs("unprotected residue was not observed\n", stderr);
    return 1;
  }
  if (cleared(&dirty)) {
    fputs("probe accepted the unprotected negative control\n", stderr);
    return 1;
  }
  puts("PASS: positive probe and unprotected residue controls");
  return 0;
}

int main(int argc, char **argv) {
  if (argc == 2 && strcmp(argv[1], "--self-test") == 0)
    return self_test();
#ifdef CES_HAVE_PROTECTED
  struct ces_snapshot snapshot;
  if (argc != 1)
    return 2;
  if (self_test())
    return 1;
  ces_probe(ces_protected, &snapshot);
  if (!cleared(&snapshot)) {
    fputs("protected exit retained covered state or changed a saved register\n",
          stderr);
    return 1;
  }
  puts("PASS: protected GPR, XMM, flags and 64-byte source buffer");
  return 0;
#else
  fputs("use --self-test for a probe-only build\n", stderr);
  return 2;
#endif
}
