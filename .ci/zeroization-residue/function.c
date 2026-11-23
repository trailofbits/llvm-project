// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#include "probe.h"

#ifndef CES_FUNCTION
#error CES_FUNCTION must name the test function
#endif

#ifdef CES_PROTECTED
__attribute__((zeroize_on_return))
#endif
__attribute__((noinline)) void CES_FUNCTION(void) {
  volatile unsigned char buffer[64];
  for (unsigned i = 0; i < sizeof(buffer); ++i)
    buffer[i] = 0xa5;
  ces_buffer_address = buffer;
}
