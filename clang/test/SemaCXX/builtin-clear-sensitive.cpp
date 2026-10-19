// RUN: %clang_cc1 -triple x86_64-unknown-linux-gnu -std=c++20 -fsyntax-only -verify %s

template <typename T> void clear(T *p, unsigned n) {
  __builtin_clear_sensitive(p, n); // expected-error {{address argument to __builtin_clear_sensitive must be a pointer to a non-const object ('const int *' invalid)}}
}
template void clear<int>(int *, unsigned);
template void clear<const int>(const int *, unsigned); // expected-note {{in instantiation of function template specialization 'clear<const int>' requested here}}

template <typename T> void clear_value(T v) {
  __builtin_clear_sensitive(v, sizeof(v)); // expected-error {{must be a pointer to a non-const object ('long' invalid)}}
}
template void clear_value<long>(long); // expected-note {{in instantiation of function template specialization 'clear_value<long>' requested here}}

struct Holder {
  int data[4];
  void wipe() { __builtin_clear_sensitive(data, sizeof data); }
  void wipe(int &r) { __builtin_clear_sensitive(&r, sizeof r); }
  void wipe_const() const {
    __builtin_clear_sensitive(data, sizeof data); // expected-error {{must be a pointer to a non-const object ('const int *' invalid)}}
  }
};

void null_pointer() {
  __builtin_clear_sensitive(nullptr, 1); // expected-error {{must be a pointer to a non-const object ('std::nullptr_t' invalid)}}
}

// The clear is a runtime effect and cannot be constant-evaluated.
constexpr int cleared() { // expected-error {{constexpr function never produces a constant expression}}
  int x = 1;
  __builtin_clear_sensitive(&x, sizeof x); // expected-note 2 {{subexpression not valid in a constant expression}}
  return x;
}
static_assert(cleared() == 0, ""); // expected-error {{static assertion expression is not an integral constant expression}} \
                                   // expected-note {{in call to 'cleared()'}}
