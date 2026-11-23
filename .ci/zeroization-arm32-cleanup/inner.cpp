// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
extern "C" void action(int);
extern "C" void event(int) noexcept;
extern "C" int cleanup_count;

struct Guard {
  __attribute__((always_inline)) ~Guard() {
#ifdef PRIVATE_OBSERVATION
    ++cleanup_count;
#else
    event(1);
#endif
  }
};

#ifndef WORDS
#define WORDS 6
#endif

extern "C"
#ifdef PROTECTED
    __attribute__((zeroize_on_return))
#endif
    __attribute__((noinline, section("innercode"))) int inner(int value) {
#ifdef MINIMUM
  (void)value;
  asm volatile("movw r4, #0x5511\nmovt r4, #0x7733" : : : "r4", "memory");
#else
  volatile unsigned words[WORDS];
  words[1] = value;
#ifdef SAVE_ALL
  asm volatile("movw r4, #0x5511\nmovt r4, #0x7733\n"
               "mov r5, #5\nmov r6, #6\nmov r7, #7\nmov r8, #8\n"
               "mov r9, #9\nmov r10, #10\nmov r11, #11"
               :
               : "r"(words)
               : "r4", "r5", "r6", "r7", "r8", "r9", "r10", "r11", "memory");
#else
  asm volatile("movw r4, #0x5511\nmovt r4, #0x7733"
               :
               : "r"(words)
               : "r4", "memory");
#endif
#endif
  Guard guard;
  action(0);
#ifdef MINIMUM
  return 7;
#else
  return words[1];
#endif
}
