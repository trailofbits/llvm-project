// RUN: %clang_cc1 -triple x86_64-unknown-linux-gnu -fsyntax-only -verify %s
// RUN: %clang_cc1 -triple i386-unknown-linux-gnu -fsyntax-only -verify %s

#if !__has_builtin(__builtin_clear_sensitive)
#error __builtin_clear_sensitive is not available
#endif

typedef __SIZE_TYPE__ size_t;

struct S {
  int a;
};

void accepted(void *p, size_t n, volatile char *v, int arr[8], struct S *s,
              __attribute__((address_space(1))) int *g, unsigned char u) {
  __builtin_clear_sensitive(p, n);
  __builtin_clear_sensitive(v, 4);
  __builtin_clear_sensitive(arr, sizeof(int) * 8);
  __builtin_clear_sensitive(s, sizeof *s);
  __builtin_clear_sensitive(g, 16);
  __builtin_clear_sensitive(p, u);
  __builtin_clear_sensitive((void *)0, 0);
}

void rejected(const char *c, int i, void (*f)(void), struct S s) {
  __builtin_clear_sensitive(c, 1); // expected-error {{address argument to __builtin_clear_sensitive must be a pointer to a non-const object ('const char *' invalid)}}
  __builtin_clear_sensitive(i, 1); // expected-error {{must be a pointer to a non-const object ('int' invalid)}}
  __builtin_clear_sensitive(f, 1); // expected-error {{must be a pointer to a non-const object ('void (*)(void)' invalid)}}
  __builtin_clear_sensitive(s, 1); // expected-error {{must be a pointer to a non-const object ('struct S' invalid)}}
  __builtin_clear_sensitive(&i); // expected-error {{too few arguments to function call, expected 2, have 1}}
  __builtin_clear_sensitive(&i, 1, 2); // expected-error {{too many arguments to function call, expected 2, have 3}}
  __builtin_clear_sensitive(&i, &i); // expected-error {{incompatible pointer to integer conversion}}
  __builtin_clear_sensitive((void *)0, 8); // expected-warning {{null passed to a callee that requires a non-null argument}}
}

void returns_void(int *p) {
  int r = __builtin_clear_sensitive(p, sizeof *p); // expected-error {{initializing 'int' with an expression of incompatible type 'void'}}
}
