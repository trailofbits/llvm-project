// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#ifdef PROTECTED
#define CLEAR __attribute__((zeroize_on_return))
#else
#define CLEAR
#endif
extern "C" void action();
extern "C" void cleanup_event();
struct Guard {
  ~Guard() noexcept(false) { cleanup_event(); }
};
extern "C" CLEAR __attribute__((noinline)) int inner(int value) {
  volatile unsigned words[6];
  words[1] = value;
  asm volatile("" : : "r"(words) : "r4", "memory");
  Guard guard;
  action();
  return words[1];
}
