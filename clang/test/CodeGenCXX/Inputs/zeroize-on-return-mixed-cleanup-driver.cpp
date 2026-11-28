extern "C" unsigned mixed(unsigned);
static unsigned Cleanups;

extern "C" void record_cleanup() noexcept { ++Cleanups; }

extern "C" void action(unsigned Mode) {
  if (Mode == 1 || Mode == 2)
    throw 7;
  if (Mode == 3 || Mode == 12)
    throw 23u;
}

int main() {
  for (unsigned Mode = 0; Mode != 4; ++Mode) {
    Cleanups = 0;
    try {
      unsigned Result = mixed(Mode);
      if (Mode > 1 || Result != (Mode == 0 ? 10u : 18u))
        return 1;
    } catch (unsigned Value) {
      if (Mode < 2 || Value != 23u)
        return 2;
    } catch (...) {
      return 3;
    }
    if (Cleanups != 1)
      return 4;
  }
}
