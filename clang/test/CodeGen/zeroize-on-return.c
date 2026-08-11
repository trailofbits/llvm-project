// RUN: %clang_cc1 -triple x86_64-unknown-linux-gnu %s -emit-llvm -std=c23 -o - | FileCheck %s --check-prefixes=CHECK,NOFLAG
// RUN: %clang_cc1 -triple x86_64-unknown-linux-gnu %s -emit-llvm -std=c23 -fzero-call-used-regs=skip -o - | FileCheck %s --check-prefixes=CHECK,SKIP
// RUN: %clang_cc1 -triple x86_64-unknown-linux-gnu %s -emit-llvm -std=c23 -fzero-call-used-regs=used-gpr -o - | FileCheck %s --check-prefixes=CHECK,USEDGPR
// RUN: %clang_cc1 -triple x86_64-unknown-linux-gnu %s -emit-llvm -std=c23 -fzero-call-used-regs=all -o - | FileCheck %s --check-prefixes=CHECK,ALL

// A protected function requests register clearing and stack clearing together,
// and does so identically under every command-line mode: the attribute's
// guarantee is a minimum that -fzero-call-used-regs may not narrow.

// CHECK:     define {{.*}} @no_attribute() #[[PLAIN:[0-9]+]]
// CHECK:     define {{.*}} @zeroize_std() #[[PROT:[0-9]+]]
// CHECK:     define {{.*}} @zeroize_gnu() #[[PROT]]
// CHECK:     define {{.*}} @zeroize_and_skip() #[[PROT]]
// CHECK:     define {{.*}} @zeroize_on_decl() #[[PROT]]
// CHECK:     define {{.*}} @caller() #[[PLAIN]]

// The request describes the function, not calls to it. Unlike
// zero_call_used_regs, calling a protected function leaves the call
// instruction alone.
// CHECK:       call void @zeroize_std(){{$}}

// An explicitly annotated main keeps both requests. The exemption that strips
// the command-line default from an un-annotated main still applies, and
// zero-call-used-regs.c is what pins that.
// CHECK:     define {{.*}} @main() #[[PROT]]

// Which attribute group comes first depends on the mode, so these are -DAG.
// Every line is anchored on the closing brace: LLVM prints string attributes
// in alphabetical order, so "zero-call-used-regs" and "zeroize-stack" both
// sort after "target-features", and a line that ends before them proves they
// are absent rather than merely unmatched.

// CHECK-DAG:   attributes #[[PROT]] = {{.*}}"zero-call-used-regs"="all" "zeroize-stack"="used" }

// An un-annotated function follows the command line, and never gets a stack
// request: nothing on the command line asks for stack zeroization.
// NOFLAG-DAG:  attributes #[[PLAIN]] = {{.*}}"target-features"={{[^ ]*}} }
// SKIP-DAG:    attributes #[[PLAIN]] = {{.*}}"target-features"={{[^ ]*}} }
// USEDGPR-DAG: attributes #[[PLAIN]] = {{.*}}"zero-call-used-regs"="used-gpr" }
// ALL-DAG:     attributes #[[PLAIN]] = {{.*}}"zero-call-used-regs"="all" }

void no_attribute(void) {}

[[clang::zeroize_on_return]] void zeroize_std(void) {}

__attribute__((zeroize_on_return)) void zeroize_gnu(void) {}

// zeroize_on_return wins over an explicit weaker request on the same function.
// Which of the two the user meant is issue #7; that it cannot come out weaker
// than "all" is settled.
__attribute__((zeroize_on_return)) __attribute__((zero_call_used_regs("skip")))
void zeroize_and_skip(void) {}

// The attribute is inheritable, so writing it on a prototype reaches the
// definition.
[[clang::zeroize_on_return]] void zeroize_on_decl(void);
void zeroize_on_decl(void) {}

void caller(void) { zeroize_std(); }

[[clang::zeroize_on_return]] int main(void) { return 0; }
