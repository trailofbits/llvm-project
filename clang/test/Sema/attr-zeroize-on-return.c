// RUN: %clang_cc1 -triple x86_64-unknown-linux-gnu -fsyntax-only -verify -std=c23 %s

#if !__has_attribute(zeroize_on_return)
#error "zeroize_on_return is not available via __has_attribute"
#endif

#if !__has_c_attribute(clang::zeroize_on_return)
#error "clang::zeroize_on_return is not available via __has_c_attribute"
#endif

// Both spellings apply to a definition and to a prototype.
[[clang::zeroize_on_return]] void std_definition(void) {}
[[clang::zeroize_on_return]] void std_prototype(void);

__attribute__((zeroize_on_return)) void gnu_definition(void) {}
void gnu_prototype(void) __attribute__((zeroize_on_return));
void empty_arguments(void) __attribute__((zeroize_on_return()));

// The attribute is inheritable, so a prototype carrying it reaches the
// definition in the same translation unit.
[[clang::zeroize_on_return]] void redeclared(void);
void redeclared(void) {}

// It is a single request, so it takes no arguments.
// expected-error@+1 {{'zeroize_on_return' attribute takes no arguments}}
__attribute__((zeroize_on_return(2))) void arg_int(void) {}
// expected-error@+1 {{'zeroize_on_return' attribute takes no arguments}}
__attribute__((zeroize_on_return("all"))) void arg_string(void) {}
// expected-error@+1 {{'zeroize_on_return' attribute takes no arguments}}
__attribute__((zeroize_on_return(1, 2))) void arg_multiple(void) {}

// Functions only, and misuse is an error rather than an ignored attribute.
// expected-error@+1 {{'zeroize_on_return' attribute only applies to functions}}
__attribute__((zeroize_on_return)) int global_var;
// expected-error@+1 {{'clang::zeroize_on_return' attribute only applies to functions}}
[[clang::zeroize_on_return]] int std_global_var;
// expected-error@+1 {{'zeroize_on_return' attribute only applies to functions}}
struct __attribute__((zeroize_on_return)) S { int x; };
// expected-error@+1 {{'zeroize_on_return' attribute only applies to functions}}
typedef int my_int __attribute__((zeroize_on_return));

// The attribute appertains to the declared variable, not to the function type
// it points at.
// expected-error@+1 {{'zeroize_on_return' attribute only applies to functions}}
__attribute__((zeroize_on_return)) void (*fp)(void);

void local(void) {
  // expected-error@+1 {{'zeroize_on_return' attribute only applies to functions}}
  __attribute__((zeroize_on_return)) int x;
  (void)x;
}

// Both spellings must reject the incompatible attribute in either order.
void naked_first(void) __attribute__((naked, zeroize_on_return));
// expected-error@-1 {{'zeroize_on_return' and 'naked' attributes are not compatible}}
// expected-note@-2 {{conflicting attribute is here}}

void zeroize_first(void) __attribute__((zeroize_on_return, naked));
// expected-error@-1 {{'naked' and 'zeroize_on_return' attributes are not compatible}}
// expected-note@-2 {{conflicting attribute is here}}

[[gnu::naked, clang::zeroize_on_return]] void std_naked_first(void);
// expected-error@-1 {{'clang::zeroize_on_return' and 'gnu::naked' attributes are not compatible}}
// expected-note@-2 {{conflicting attribute is here}}

[[clang::zeroize_on_return, gnu::naked]] void std_zeroize_first(void);
// expected-error@-1 {{'gnu::naked' and 'clang::zeroize_on_return' attributes are not compatible}}
// expected-note@-2 {{conflicting attribute is here}}

// The same conflict must be diagnosed when the attributes are on redeclarations.
void naked_redecl(void) __attribute__((naked)); // expected-note {{conflicting attribute is here}}
void naked_redecl(void) __attribute__((zeroize_on_return));
// expected-error@-1 {{'zeroize_on_return' and 'naked' attributes are not compatible}}

void zeroize_redecl(void) __attribute__((zeroize_on_return));
// expected-note@-1 {{conflicting attribute is here}}
void zeroize_redecl(void) __attribute__((naked));
// expected-error@-1 {{'naked' and 'zeroize_on_return' attributes are not compatible}}

// Existing register-only annotations retain their previous behavior.
void register_only_naked(void) __attribute__((naked, zero_call_used_regs("all")));
