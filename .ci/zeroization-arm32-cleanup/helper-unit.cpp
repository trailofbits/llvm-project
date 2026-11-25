// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#include <cstdint>
#include <cstdio>
#include <unwind.h>

struct Context {
  unsigned regs[16];
};
extern "C" unsigned invoke_checked(void *, unsigned, void *, void *);
extern "C" unsigned phase_personality(unsigned, void *, void *);
extern "C" unsigned helper_personality(unsigned, void *, void *);
extern "C" char after_cleanup[], install_helper[], landing[];
static unsigned calls, fail_at, delegate_result, selector;
static bool in_helper;
static unsigned record[4];
static bool fails() { return ++calls == fail_at; }
extern "C" void action() {}
extern "C" void event(int) noexcept {}

extern "C" _Unwind_VRS_Result
__wrap__Unwind_VRS_Get(_Unwind_Context *raw, _Unwind_VRS_RegClass cls,
                       uint32_t reg, _Unwind_VRS_DataRepresentation rep,
                       void *value) {
  if (fails() || cls || rep || reg > 15)
    return _UVRSR_FAILED;
  *static_cast<unsigned *>(value) = reinterpret_cast<Context *>(raw)->regs[reg];
  return _UVRSR_OK;
}
extern "C" _Unwind_VRS_Result
__wrap__Unwind_VRS_Set(_Unwind_Context *raw, _Unwind_VRS_RegClass cls,
                       uint32_t reg, _Unwind_VRS_DataRepresentation rep,
                       void *value) {
  if (fails() || cls || rep || reg > 15)
    return _UVRSR_FAILED;
  reinterpret_cast<Context *>(raw)->regs[reg] = *static_cast<unsigned *>(value);
  return _UVRSR_OK;
}
extern "C" _Unwind_Reason_Code __wrap___gnu_unwind_frame(_Unwind_Exception *,
                                                         _Unwind_Context *raw) {
  if (fails())
    return _URC_FAILURE;
  auto &ctx = *reinterpret_cast<Context *>(raw);
  if (!in_helper) {
    const auto *words = reinterpret_cast<const unsigned *>(ctx.regs[13]);
    ctx.regs[4] = words[6];
    ctx.regs[15] = words[7];
    ctx.regs[13] += 32;
  }
  return _URC_OK;
}
extern "C" _Unwind_Reason_Code
__wrap___gxx_personality_v0(_Unwind_State, _Unwind_Exception *,
                            _Unwind_Context *raw) {
  if (fails())
    return _URC_FAILURE;
  auto &ctx = *reinterpret_cast<Context *>(raw);
  ctx.regs[1] = selector;
  ctx.regs[15] = reinterpret_cast<unsigned>(landing);
  return static_cast<_Unwind_Reason_Code>(delegate_result);
}
struct Case {
  unsigned delegated, selector, state, expected;
  bool helper, completed;
};
static constexpr Case Cases[] = {
    {8, 0, 1, 8, false, false}, {6, 0, 1, 6, false, false},
    {7, 0, 1, 8, false, false}, {7, 1, 1, 7, false, false},
    {7, 2, 1, 7, false, false}, {7, ~0U, 1, 9, false, false},
    {8, 0, 1, 8, false, true},  {8, 0, 2, 8, false, false},
    {8, 0, 1, 7, true, false},  {8, 0, 2, 8, true, false},
};
static Context context_for(const Case &test) {
  Context ctx{};
  ctx.regs[4] = 0x77335511;
  ctx.regs[13] = 0x12340000;
  ctx.regs[15] = reinterpret_cast<unsigned>(landing);
  if (test.completed) {
    ctx.regs[15] = reinterpret_cast<unsigned>(after_cleanup);
    ctx.regs[4] = reinterpret_cast<unsigned>(record);
  }
  if (!test.helper && test.state == 2)
    ctx.regs[4] = reinterpret_cast<unsigned>(record);
  if (test.helper && test.state == 1) {
    ctx.regs[15] = reinterpret_cast<unsigned>(install_helper);
    ctx.regs[2] = reinterpret_cast<unsigned>(landing);
  }
  return ctx;
}
static bool handler_preserved(const Context &ctx, unsigned installed_selector) {
  return ctx.regs[1] == installed_selector && ctx.regs[4] == 0x77335511 &&
         ctx.regs[13] == 0x12340000 &&
         ctx.regs[15] == reinterpret_cast<unsigned>(landing);
}
static bool run_case(const Case &test, unsigned failure) {
  record[0] = 0x1919;
  record[1] = reinterpret_cast<unsigned>(landing);
  record[2] = 0;
  record[3] = reinterpret_cast<unsigned>(after_cleanup);
  Context ctx = context_for(test);
  in_helper = test.helper;
  selector = test.selector;
  delegate_result = test.delegated;
  calls = 0;
  fail_at = failure;
  auto personality = test.helper ? helper_personality : phase_personality;
  unsigned actual = invoke_checked(reinterpret_cast<void *>(personality),
                                   test.state, nullptr, &ctx);
  unsigned expected = failure ? 9 : test.expected;
  if (actual != expected) {
    std::printf("FAIL helper-status actual=%u expected=%u\n", actual, expected);
    return false;
  }
  if (!failure && !test.helper && test.expected == 7 &&
      !handler_preserved(ctx, test.selector)) {
    std::puts("FAIL handler-context");
    return false;
  }
  return true;
}
int main() {
  unsigned total = 0;
  for (const Case &test : Cases) {
    if (!run_case(test, 0))
      return 1;
    unsigned count = calls;
    ++total;
    for (unsigned failure = 1; failure <= count; ++failure) {
      if (!run_case(test, failure))
        return 1;
      ++total;
    }
  }
  std::printf(
      "PASS raw-helper cases=%u physical-registers=checked memory=unobserved\n",
      total);
}
