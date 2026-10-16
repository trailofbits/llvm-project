// RUN: %clang_cc1 -triple x86_64-unknown-linux-gnu -std=c++20 -fsyntax-only -verify %s

#include "Inputs/std-coroutine.h"

struct Task {
  struct promise_type {
    Task get_return_object();
    std::suspend_never initial_suspend() noexcept;
    std::suspend_never final_suspend() noexcept;
    std::suspend_never yield_value(int);
    void return_void();
    void unhandled_exception();
  };
};

[[clang::zeroize_on_return]] // expected-note{{'zeroize_on_return' attribute specified here}}
Task protected_return() {
  co_return; // expected-error{{'co_return' cannot be used in a function with 'zeroize_on_return'}}
}

[[clang::zeroize_on_return]] // expected-note{{'zeroize_on_return' attribute specified here}}
Task protected_await() {
  // expected-error@+1{{'co_await' cannot be used in a function with 'zeroize_on_return'}}
  co_await std::suspend_never{};
}

[[clang::zeroize_on_return]] // expected-note{{'zeroize_on_return' attribute specified here}}
Task protected_yield() {
  co_yield 1; // expected-error{{'co_yield' cannot be used in a function with 'zeroize_on_return'}}
}

[[clang::zeroize_on_return]] // expected-note{{'zeroize_on_return' attribute specified here}}
Task inherited();
Task inherited() {
  co_return; // expected-error{{'co_return' cannot be used in a function with 'zeroize_on_return'}}
}

template <class T>
[[clang::zeroize_on_return]] // expected-note{{'zeroize_on_return' attribute specified here}}
Task protected_template(T) {
  co_return; // expected-error{{'co_return' cannot be used in a function with 'zeroize_on_return'}}
}

void protected_lambda() {
  // expected-note@+1{{'zeroize_on_return' attribute specified here}}
  auto f = []() __attribute__((zeroize_on_return)) -> Task {
    // expected-error@+1{{'co_return' cannot be used in a function with 'zeroize_on_return'}}
    co_return;
  };
}

Task ordinary_coroutine() { // expected-note{{previous definition is here}}
  co_await std::suspend_never{};
  co_yield 1;
  co_return;
}

[[clang::zeroize_on_return]]
Task nested_lambda() {
  return []() -> Task { co_return; }();
}

// Adding the attribute after a completed coroutine body is already diagnosed.
// expected-warning@+1{{attribute declaration must precede definition}}
[[clang::zeroize_on_return]] Task ordinary_coroutine();
