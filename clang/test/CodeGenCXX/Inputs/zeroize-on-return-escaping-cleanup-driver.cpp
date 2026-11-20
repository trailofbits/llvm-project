// Link with zeroize-on-return-escaping-cleanup.cpp as a separate translation unit.
extern "C" unsigned outgoing(unsigned);

static unsigned Cleanups;
static bool ShouldThrow;

extern "C" void record_cleanup() noexcept { ++Cleanups; }

extern "C" void may_throw() {
  if (ShouldThrow)
    throw 19;
}

int main() {
  if (outgoing(11) != 14 || Cleanups != 1)
    return 1;
  ShouldThrow = true;
  try {
    (void)outgoing(11);
  } catch (int Value) {
    return Value == 19 && Cleanups == 2 ? 0 : 2;
  }
  return 3;
}
