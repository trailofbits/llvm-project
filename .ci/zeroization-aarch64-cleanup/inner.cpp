extern "C" void event(int) noexcept;
#ifdef ORDINARY_RETURN
extern "C" void action(int) noexcept;
#else
extern "C" void action(int);
#endif

struct Guard {
  __attribute__((always_inline)) ~Guard() noexcept { event(1); }
};

#ifdef PROTECTED
#define CLEAR __attribute__((zeroize_on_return))
#else
#define CLEAR
#endif

extern "C" CLEAR __attribute__((noinline)) int inner(int value) {
  Guard guard;
  asm volatile("mov x19, #101\nmov x20, #102\nfmov d8, xzr"
               :
               :
               : "x19", "x20", "v8");
#ifndef RESERVE_X21
  asm volatile("mov x21, #103" : : : "x21");
#endif
#ifdef ORDINARY_RETURN
  action(value);
#else
  try {
    action(value);
  } catch (long adjustment) {
    return value + adjustment;
  }
#endif
  return value;
}
