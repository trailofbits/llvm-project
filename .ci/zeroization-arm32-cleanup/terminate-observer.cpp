// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#include <cstdio>
#include <cstdlib>
#include <exception>
extern "C" int inner(int);
static unsigned calls, cleanups;
static bool throwing;
extern "C" void action() {
  ++calls;
  if (throwing)
    throw 17;
}
extern "C" void cleanup_event() {
  ++cleanups;
  if (throwing)
    throw 29L;
}
[[noreturn]] static void observe_terminate() noexcept {
  bool correct = calls == 1 && cleanups == 1;
  std::printf("terminate callback calls=%u cleanups=%u correct=%d\n", calls,
              cleanups, correct);
  std::fflush(stdout);
  std::_Exit(correct ? 0 : 91);
}
int main(int argc, char **argv) {
  if (argc != 2)
    return 92;
  throwing = std::atoi(argv[1]) != 0;
  std::set_terminate(observe_terminate);
  int value = 0;
  try {
    value = inner(7);
  } catch (int) {
    return 94;
  } catch (long) {
    return 95;
  }
  bool correct = !throwing && value == 7 && calls == 1 && cleanups == 1;
  std::printf("normal calls=%u cleanups=%u correct=%d\n", calls, cleanups,
              correct);
  return correct ? 0 : 93;
}
