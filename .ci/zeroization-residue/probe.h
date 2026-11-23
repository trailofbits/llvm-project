// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#ifndef CES_RESIDUE_PROBE_H
#define CES_RESIDUE_PROBE_H

struct ces_snapshot {
  unsigned long long gpr[9];
  unsigned long long flags;
  unsigned char xmm[16][16];
  unsigned char buffer[64];
  unsigned long long preserved[3];
};

extern const volatile unsigned char *ces_buffer_address;
void ces_probe(void (*function)(void), struct ces_snapshot *snapshot);
void ces_zero_fixture(void);
void ces_unprotected(void);
#ifdef CES_HAVE_PROTECTED
void ces_protected(void);
#endif

#endif
