// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <unwind.h>

extern "C" int inner(int), abi_enter(int), markers_ok();
extern "C" char __start_middlecode[], __stop_middlecode[];
extern "C" char __start_outercode[], __stop_outercode[];
static unsigned frame_size, inner_size, input, observed, events, branch_events;
static unsigned original_sp;
static bool protected_case, distinct_exits;
static const char *mode;
static int token, released;
static _Unwind_Exception exception;
static constexpr char ForcedClass[] = "TESTFRC1";

[[noreturn]] static void fail(const char *reason, int status = 70) {
  std::printf("FAIL reason=%s\n", reason);
  std::_Exit(status);
}

static void require(bool condition, const char *reason) {
  if (!condition)
    fail(reason);
}

extern "C" void event(int frame) noexcept {
  if (frame == 3) {
    ++branch_events;
    return;
  }
  require(frame == static_cast<int>(events + 1), "destructor-order");
  if (frame == 2)
    require(markers_ok(), "caller-context");
  ++events;
}

struct OuterGuard {
  ~OuterGuard() { event(2); }
};

extern "C" __attribute__((noinline, section("middlecode"))) int
middle(int value) {
  OuterGuard guard;
  return inner(value) + 5;
}

extern "C" __attribute__((noinline, section("outercode"))) int
outer(int value) {
  if (!std::strcmp(mode, "forced"))
    return middle(value);
  try {
    int result = middle(value);
    require(!std::strcmp(mode, "normal") && result == value + 5,
            "normal-result");
    require(markers_ok(), "caller-context");
  } catch (int *object) {
    require(!std::strcmp(mode, "typed") && object == &token,
            "exception-identity");
    require(markers_ok(), "caller-context");
  }
  return 0;
}

static unsigned region(_Unwind_Context *context) {
  unsigned pc = (_Unwind_GetIP(context) & ~1U) - 1;
  unsigned start = reinterpret_cast<unsigned>(&inner) & ~1U;
  if (pc >= start && pc < start + inner_size)
    return 1;
  if (pc >= reinterpret_cast<unsigned>(__start_middlecode) &&
      pc < reinterpret_cast<unsigned>(__stop_middlecode))
    return 2;
  if (pc >= reinterpret_cast<unsigned>(__start_outercode) &&
      pc < reinterpret_cast<unsigned>(__stop_outercode))
    return 3;
  return 0;
}

static void observe_frame(_Unwind_Context *context) {
  require(original_sp && !observed, "ambiguous-original-frame");
  const volatile unsigned char *bytes =
      reinterpret_cast<const volatile unsigned char *>(original_sp);
  unsigned residue = 0;
  std::printf("FRAME bytes=%u hex=", frame_size);
  for (unsigned i = 0; i != frame_size; ++i) {
    unsigned value = bytes[i];
    residue |= value;
    std::printf("%02x", value);
  }
  std::puts("");
  if (protected_case && residue)
    fail("original-residue", 78);
  require(protected_case || residue, "missing-unprotected-residue");
  require(_Unwind_GetGR(context, 13) == original_sp, "original-frame-identity");
  ++observed;
}

static void check_events() {
  require(events == 2, "missing-destructor");
  require(branch_events == (distinct_exits ? input % 2 : 0), "cleanup-branch");
}

static void release_exception(_Unwind_Reason_Code reason,
                              _Unwind_Exception *object) {
  require(reason == _URC_FOREIGN_EXCEPTION_CAUGHT && object == &exception,
          "exception-release");
  ++released;
}

static _Unwind_Reason_Code stop(int version, _Unwind_Action actions,
                                _Unwind_Exception_Class kind,
                                _Unwind_Exception *object,
                                _Unwind_Context *context, void *) {
  require(version == 1 && object == &exception, "forced-callback");
  require(!std::memcmp(kind, ForcedClass, 8), "forced-class");
  require(actions & _UA_FORCE_UNWIND, "forced-action");
  require(!(actions & _UA_END_OF_STACK), "missing-outer-frame");
  unsigned frame = region(context);
  if (frame == 1) {
    if (!events)
      original_sp = _Unwind_GetGR(context, 13);
    else
      observe_frame(context);
  }
  if (frame == 3) {
    check_events();
    require(observed == 1, "missing-frame-observation");
    _Unwind_DeleteException(&exception);
    require(released == 1, "release-count");
    std::puts("PASS mode=forced");
    std::_Exit(0);
  }
  return _URC_NO_REASON;
}

extern "C" void action(int) {
  if (!std::strcmp(mode, "typed"))
    throw &token;
  if (!std::strcmp(mode, "forced")) {
    std::memcpy(exception.exception_class, ForcedClass, 8);
    exception.exception_cleanup = release_exception;
    _Unwind_ForcedUnwind(&exception, stop, nullptr);
    fail("forced-unwind-returned");
  }
}

int main(int argc, char **argv) {
  require(argc == 7, "arguments");
  std::setvbuf(stdout, nullptr, _IONBF, 0);
  protected_case = !std::strcmp(argv[1], "protected");
  mode = argv[2];
  frame_size = std::strtoul(argv[3], nullptr, 0);
  inner_size = std::strtoul(argv[4], nullptr, 0);
  input = std::strtoul(argv[5], nullptr, 0);
  distinct_exits = !std::strcmp(argv[6], "distinct");
  require(protected_case || !std::strcmp(argv[1], "control"), "variant");
  require(distinct_exits || !std::strcmp(argv[6], "source"), "fixture-kind");
  require(frame_size >= 8 && frame_size <= 224 && frame_size % 8 == 0,
          "frame-bounds");
  require(inner_size && inner_size <= 65536, "code-bounds");
  require(abi_enter(input) == 0, "abi-entry");
  check_events();
  std::printf("PASS mode=%s\n", mode);
}
