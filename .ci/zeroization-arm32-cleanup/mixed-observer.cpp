// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <unwind.h>

extern "C" int inner(int), abi_enter(int), markers_ok();
extern "C" char __start_outercode[], __stop_outercode[];
extern "C" {
int scenario, token = 17;
unsigned frame_size;
}
static unsigned events[5], boundaries, deleted, depth, initial_depth;
static bool protected_case, catch_all;
static int replacement = 29;
static _Unwind_Exception forced;

[[noreturn]] static void fail(const char *reason) {
  std::printf("FAIL reason=%s\n", reason);
  std::_Exit(84);
}
static void require(bool value, const char *reason) {
  if (!value)
    fail(reason);
}
extern "C" void event(int id) noexcept {
  require(id > 0 && id < 5, "handler-identity");
  ++events[id];
}
static void delete_forced(_Unwind_Reason_Code why, _Unwind_Exception *object) {
  require(why == _URC_FOREIGN_EXCEPTION_CAUGHT && object == &forced,
          "forced-delete");
  ++deleted;
}
static void check_forced_header(int version, _Unwind_Action actions,
                                _Unwind_Exception_Class klass,
                                _Unwind_Exception *object) {
  require(version == 1 && (actions & _UA_FORCE_UNWIND) && object == &forced,
          "forced-interface");
  bool known =
      !std::memcmp(klass, "MIXFRC01", 8) || !std::memcmp(klass, "GNUCFOR\0", 8);
  require(known && !std::memcmp(klass, forced.exception_class, 8),
          "forced-class");
}
static _Unwind_Reason_Code stop(int version, _Unwind_Action actions,
                                _Unwind_Exception_Class klass,
                                _Unwind_Exception *object,
                                _Unwind_Context *context, void *) {
  check_forced_header(version, actions, klass, object);
  unsigned pc = (_Unwind_GetIP(context) & ~1U) - 1;
  if (pc >= reinterpret_cast<unsigned>(__start_outercode) &&
      pc < reinterpret_cast<unsigned>(__stop_outercode)) {
    require(events[1] == 1 && events[2] == unsigned(!catch_all),
            "forced-destructors");
    require(boundaries == unsigned(protected_case), "forced-boundary");
    require(_Unwind_GetGR(context, 4) == 0x1919 &&
                _Unwind_GetGR(context, 5) == 0x2020,
            "forced-caller");
    _Unwind_DeleteException(&forced);
    require(deleted == 1, "forced-delete-count");
    std::printf("PASS mixed scenario=5 boundaries=%u\n", boundaries);
    std::fflush(stdout);
    std::_Exit(0);
  }
  require(!(actions & _UA_END_OF_STACK), "forced-missing-caller");
  return _URC_NO_REASON;
}
static void nested() {
  if (!depth)
    return;
  --depth;
  try {
    require(inner(7) == 7, "nested-result");
  } catch (...) {
    ++depth;
    throw;
  }
  ++depth;
}
static void catch_action() {
  if (catch_all)
    event(3);
  if (scenario == 2 || scenario == 5)
    throw;
  if (scenario == 3)
    throw &replacement;
  if (scenario >= 7) {
    nested();
    if (scenario == 8)
      throw;
  }
}
static void second_handler() {
  if (scenario != 6)
    throw;
}
extern "C" void action(int stage) {
  if (stage == 2) {
    nested();
    return;
  }
  if (stage == 1) {
    catch_action();
    return;
  }
  if (stage == 3) {
    second_handler();
    return;
  }
  if (scenario == 5) {
    std::memcpy(forced.exception_class, "MIXFRC01", 8);
    forced.exception_cleanup = delete_forced;
    _Unwind_ForcedUnwind(&forced, stop, nullptr);
    fail("forced-returned");
  }
  if (scenario == 4)
    throw 42.0;
  if (scenario == 6)
    throw 42L;
  if (scenario)
    throw &token;
}
extern "C" void boundary_probe(unsigned residue, unsigned,
                               const unsigned *frame) {
  require(residue == 0, "original-residue");
  for (unsigned i = 0; i != frame_size / 4; ++i)
    require(frame[i] == 0, "original-word");
  if (initial_depth == depth)
    require(frame[-4] == 0x1919, "incoming-r4");
  ++boundaries;
}
static void check_counts() {
  unsigned calls = initial_depth + 1;
  require(events[1] == calls && events[2] == calls * unsigned(!catch_all),
          "destructors");
  static constexpr bool TypedCatch[] = {false, true, true, true, false,
                                        false, true, true, true};
  unsigned caught = catch_all ? scenario != 0 : TypedCatch[scenario];
  unsigned second = scenario == 6 && !catch_all;
  require(events[3] == calls * (caught - second) && events[4] == second,
          "catch-counts");
  static constexpr bool Escapes[] = {false, false, true,  true, false,
                                     true,  false, false, true};
  bool escapes = scenario == 4 ? !catch_all : Escapes[scenario];
  require(boundaries == calls * unsigned(escapes && protected_case),
          "cleanup-boundaries");
}
static bool expected_pointer(int *object) {
  if (scenario == 3)
    return object == &replacement;
  return (scenario == 2 || scenario == 8) && object == &token;
}
static bool expected_double(double object) {
  return scenario == 4 && object == 42.0 && !catch_all;
}
extern "C" __attribute__((noinline, section("outercode"))) int
outer(int value) {
  bool correct = false;
  try {
    correct = inner(value) == value && scenario != 2 && scenario != 3 &&
              scenario != 8;
  } catch (int *object) {
    correct = expected_pointer(object);
  } catch (double object) {
    correct = expected_double(object);
  }
  require(correct && markers_ok(), "result-or-caller");
  check_counts();
  std::printf("PASS mixed scenario=%d boundaries=%u\n", scenario, boundaries);
  return 0;
}
int main(int argc, char **argv) {
  if (argc != 6)
    return 85;
  scenario = std::atoi(argv[1]);
  protected_case = std::atoi(argv[2]);
  catch_all = std::atoi(argv[3]);
  frame_size = std::strtoul(argv[4], nullptr, 0);
  initial_depth = depth = std::strtoul(argv[5], nullptr, 0);
  return abi_enter(7);
}
