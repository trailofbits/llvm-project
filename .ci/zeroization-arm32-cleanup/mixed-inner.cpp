// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
extern "C" void action(int);
extern "C" void event(int) noexcept;
extern "C" int scenario, token;
#ifndef WORDS
#define WORDS 6
#endif
#ifdef SAVE_ALL
#define SAVED_GPRS "r4", "r5", "r6", "r7", "r8", "r9", "r10", "r11"
#else
#define SAVED_GPRS "r4"
#endif
struct Guard {
  int id;
  __attribute__((always_inline)) ~Guard() { event(id); }
};
#ifdef PROTECTED
#define CLEAR __attribute__((zeroize_on_return))
#else
#define CLEAR
#endif

extern "C" CLEAR
    __attribute__((noinline, section("innercode"))) int inner(int value) {
  volatile unsigned words[WORDS];
  words[1] = value;
  asm volatile("movw r4,#0x5511\nmovt r4,#0x7733"
               :
               : "r"(words)
               : SAVED_GPRS, "memory");
  Guard outer{1};
#ifdef CATCH_ALL
  // Keep the published WITH_CATCH shape: the handler makes a second throwing
  // call.
  try {
    action(0);
  } catch (...) {
    action(1);
  }
#else
  try {
    Guard local{2};
    action(0);
  } catch (int *caught) {
    event(caught == &token ? 3 : 9);
    action(1);
  } catch (long) {
    event(4);
    action(3);
  }
#endif
  return words[1];
}
