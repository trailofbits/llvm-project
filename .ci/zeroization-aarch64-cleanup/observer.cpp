#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <unwind.h>

extern "C" int inner(int);
extern "C" int abi_enter(int);
extern "C" int markers_ok();

enum class Mode { Normal, Caught, Typed, Forced };
static Mode mode;
static bool protected_frame;
static unsigned frame_size;
static unsigned lr_offset;
static unsigned events;
static unsigned observations;
static int token;
static _Unwind_Ptr original_sp;
static _Unwind_Ptr original_ip;
static unsigned long original_lr;
static _Unwind_Exception exception;
static bool released;
static constexpr _Unwind_Exception_Class forced_class = 0x5445535446524331ULL;

[[noreturn]] static void fail(int status, const char *reason) {
  std::printf("FAIL reason=%s\n", reason);
  std::_Exit(status);
}

extern "C" void event(int frame) noexcept {
  if (frame != static_cast<int>(events + 1))
    fail(21, "destructor-order");
  if (frame == 2 && !markers_ok())
    fail(22, "caller-registers");
  ++events;
}

struct OuterGuard {
  ~OuterGuard() { event(2); }
};

extern "C" __attribute__((noinline)) int middle(int value) {
  OuterGuard guard;
  return inner(value) + 5;
}

static void check_typed_exception(int *object) {
  if (mode != Mode::Typed || object != &token || !markers_ok())
    fail(33, "exception-identity");
}

extern "C" __attribute__((noinline)) int outer(int value) {
  try {
    int result = middle(value);
    int adjustment = mode == Mode::Caught ? 11 : 0;
    if (result != value + adjustment + 5 || !markers_ok())
      fail(31, "normal-result");
    if (mode != Mode::Normal && mode != Mode::Caught)
      fail(32, "missing-exception");
  } catch (int *object) {
    check_typed_exception(object);
  }
  return 0;
}

static void observe_frame(_Unwind_Ptr address) {
  auto bytes = reinterpret_cast<const volatile unsigned char *>(address);
  unsigned nonzero = 0;
  std::printf("FRAME bytes=%u hex=", frame_size);
  for (unsigned i = 0; i != frame_size; ++i) {
    unsigned byte = bytes[i];
    nonzero += byte != 0;
    std::printf("%02x", byte);
  }
  std::printf("\nFRAME nonzero=%u\n", nonzero);
  if (protected_frame && nonzero != 0)
    fail(74, "original-frame-residue");
  if (!protected_frame && nonzero == 0)
    fail(75, "control-has-no-residue");
}

static void observe_context(_Unwind_Context *context, _Unwind_Ptr sp) {
  if (_Unwind_GetGR(context, 19) != 0x1919 ||
      _Unwind_GetGR(context, 20) != 0x2020)
    fail(62, "restored-context");
  auto helper = _Unwind_GetGR(context, 21);
  if (helper + 32 != sp)
    fail(73, "helper-overlap");
  auto record = reinterpret_cast<const volatile unsigned long *>(helper);
  std::printf("HELPER low=%#lx original=%#lx words=%#lx,%#lx,%#lx,%#lx\n",
              helper, sp, record[0], record[1], record[2], record[3]);
  if (record[1] != 0x2121)
    fail(76, "caller-x21");
  if (record[0] != original_lr || record[2] != 0 ||
      record[3] != _Unwind_GetIP(context))
    fail(77, "helper-context");
  std::puts("CONTEXT restored=1 helper-disjoint=1");
}

static void observe_cleanup(_Unwind_Context *context) {
  auto sp = _Unwind_GetCFA(context);
  auto ip = _Unwind_GetIP(context);
  if (events == 0) {
    original_sp = sp;
    original_ip = ip;
    original_lr = *reinterpret_cast<const unsigned long *>(sp + lr_offset);
    return;
  }
  if (events != 1 || observations++ != 0 || sp != original_sp ||
      ip == original_ip)
    fail(61, "original-frame-identity");
  if (protected_frame)
    observe_context(context, sp);
  observe_frame(sp);
}

static void release_exception(_Unwind_Reason_Code reason,
                              _Unwind_Exception *object) {
  if (reason != _URC_FOREIGN_EXCEPTION_CAUGHT || object != &exception ||
      released)
    fail(47, "exception-release");
  released = true;
}

[[noreturn]] static void finish_forced() {
  if (events != 2 || observations != 1)
    fail(43, "missing-cleanup-observation");
  _Unwind_DeleteException(&exception);
  if (!released)
    fail(48, "missing-release");
  std::puts("PASS mode=forced");
  std::_Exit(0);
}

static void check_forced(int version, _Unwind_Action actions,
                         _Unwind_Exception_Class kind,
                         _Unwind_Exception *object) {
  if (version != 1 || kind != forced_class || object != &exception)
    fail(41, "forced-interface");
  if (!(actions & _UA_FORCE_UNWIND) || !(actions & _UA_CLEANUP_PHASE) ||
      (actions & _UA_END_OF_STACK))
    fail(42, "forced-actions");
}

// This six-argument signature is required by _Unwind_Stop_Fn.
static _Unwind_Reason_Code stop(int version, _Unwind_Action actions,
                                _Unwind_Exception_Class kind,
                                _Unwind_Exception *object,
                                _Unwind_Context *context, void *) {
  check_forced(version, actions, kind, object);
  auto region = _Unwind_GetRegionStart(context);
  if (region == reinterpret_cast<_Unwind_Ptr>(&inner))
    observe_cleanup(context);
  if (region == reinterpret_cast<_Unwind_Ptr>(&outer))
    finish_forced();
  return _URC_NO_REASON;
}

extern "C" void action(int) {
  if (mode == Mode::Caught)
    throw 11L;
  if (mode == Mode::Typed)
    throw &token;
  if (mode == Mode::Forced) {
    exception.exception_class = forced_class;
    exception.exception_cleanup = release_exception;
    _Unwind_ForcedUnwind(&exception, stop, nullptr);
    fail(44, "forced-returned");
  }
}

static Mode parse_mode(const char *name) {
  if (!std::strcmp(name, "normal"))
    return Mode::Normal;
  if (!std::strcmp(name, "caught"))
    return Mode::Caught;
  if (!std::strcmp(name, "typed"))
    return Mode::Typed;
  if (!std::strcmp(name, "forced"))
    return Mode::Forced;
  fail(80, "unknown-mode");
}

static unsigned number(const char *text) {
  char *end;
  unsigned long value = std::strtoul(text, &end, 10);
  if (!*text || *end || value > 4096)
    fail(80, "invalid-number");
  return value;
}

static void configure(int argc, char **argv) {
  if (argc != 6)
    fail(80, "usage-variant-mode-size-lr-offset-input");
  protected_frame = !std::strcmp(argv[1], "protected");
  if (!protected_frame && std::strcmp(argv[1], "control"))
    fail(80, "unknown-variant");
  mode = parse_mode(argv[2]);
  frame_size = number(argv[3]);
  if (!frame_size || frame_size % 16)
    fail(78, "frame-size");
  lr_offset = number(argv[4]);
  if (lr_offset % 8 || lr_offset + 8 > frame_size)
    fail(78, "lr-offset");
}

int main(int argc, char **argv) {
  std::setvbuf(stdout, nullptr, _IONBF, 0);
  configure(argc, argv);
  int result = abi_enter(number(argv[5]));
  if (result != 0 || events != 2)
    fail(45, "public-behavior");
  std::printf("PASS mode=%s\n", argv[2]);
  return 0;
}
