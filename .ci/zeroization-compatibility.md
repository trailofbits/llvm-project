# Register-zeroing compatibility baseline

This branch proposes fixture revision `91303c7f1d0138e1d24b40ee8313cf145385cf30` for
review under [tracker #60](https://github.com/trailofbits/vspells-ct-internal-notes/issues/60).
It extends the SVE upper-lane proposal at `b0632252fce3fa21c308b2db4c299eab706173e2`
and the fixed-width proposal at `657dd456bef04ccd9f04e48319fe6e0b7c174579`.
The November 14 baseline was `7932207f03ab3b3ed2fad5ea3fe2298d7e426dce`.
Acceptance of these proposed expectation changes remains pending.

## SVE first-fault register correction

AAPCS64 makes the First Fault Register (FFR) caller-saved. The SVE `all` and
`all_float` cases now require `wrffr p0.b` after P0 is cleared. Each existing
SVE expectation gains one instruction; the input IR, all four RUN variants,
and the default, streaming SME, and streaming-compatible checks are unchanged.
The five other fixture files and their hashes are unchanged.

All six fixtures and 23 compiler/FileCheck invocations pass with the correction.
The previous SVE expectations reject the extra FFR clears, and the new checks
reject the compiler that leaves FFR unchanged. This extends the proposed
baseline; acceptance remains pending. Separate FFR tests cover used-only mode,
predicate results, live FFR outputs, and diagnostics for unavailable scratch
predicates or unsupported streaming instructions.

## SVE upper-lane correction

[PR #61](https://github.com/trailofbits/llvm-project/pull/61) extends the base AAPCS64
upper-lane clear to functions with SVE. The `all` and `all_float` expectations now require
writes to V8 through V15 that preserve the low 64 bits and clear their scalable upper bits.
Those instructions also change scheduling. SVE and streaming SME therefore have separate
checks for these two functions; the SME expectations retain their previous instruction sequence.
The default and streaming-compatible expectations, fixture inputs, and all RUN variants remain.

The previous fixture failed the corrected compiler's SVE invocation. The new expectations
pass all four AArch64 invocations and reject the compiler without the SVE upper-lane correction.
The five other fixture files and their hashes remain unchanged. This amendment preserves the
six-file, 23-invocation gate; it does not claim unchanged output against either prior baseline.

## Proposed AArch64 expectations

In the fixed-width AArch64 C ABI, the caller owns the low 64 bits of V8 through V15. Each upper
half must be cleared while its low half is preserved. Two existing default-mode checks now
require the eight corresponding writes. All earlier assertions and the five other fixture files
are retained. The comparison recorded for that fixed-width proposal passed 22 of 23 variants
with the November 14 inputs and 23 of 23 with its revised expectations. Those historical results
precede the SVE upper-lane correction above.

## November 14 differences

The original baseline was `c7317d79aacf76b5eb2dc65010e574a5269838ef`. An audit of its
six unchanged files against the updated compiler passed two complete files and
12 of 22 RUN variants. Ten FileCheck failures reflected the following changes;
the audit did not demonstrate a new correctness regression or invalid fixture.

- X86 `zero-call-used-regs.ll`: the i386 `all-arg` case now clears previously dropped
  MMX-alias storage through the x87 sequence (`dc3b868835db`).
- X86 `zero-call-used-regs-i386.ll`: preserve the AL return while clearing stale AH
  and upper EAX with `movzbl` (`0eecbe54f04b`).
- X86 `zero-call-used-regs-simd.ll`: remove duplicate clears and coalesce aliases
  (upstream `879a2e61e1ef` and fixes `0eecbe54f04b`/`dc3b868835db`).
- AArch64 `zero-call-used-regs.ll`: schedule clears with the added exit dependencies,
  retaining the clears (`a5cfe6ce4a2c`).
- X86 `zero-call-used-regs-fmod.ll` and Clang `zero-call-used-regs.c`: unchanged.

The new SIMD fixture also includes its existing AVX-512F-only case, so the frozen
six-file baseline now covers 23 RUN variants. This is not a claim of byte-for-byte
compatibility with the earlier revision.

## Running the gate

Configure LLVM with Clang plus the X86 and AArch64 targets. Build the suite's
test dependencies before invoking lit, including its helper tools:

```sh
cmake --build build --target llvm-test-depends clang-test-depends
python3 .ci/check_zeroization_compatibility_test.py
python3 .ci/check_zeroization_compatibility.py --build-dir build
```

The runner uses the build's configured `llvm-lit` and checks that the CMake source
directory matches this checkout. It rejects `LLVM_ENABLE_PROFCHECK`, which replaces
FileCheck with an output sink instead of testing expectations.
The [manifest](zeroization-compatibility.json)
contains complete SHA256 hashes; a shallow checkout does not need the baseline's
Git object. Changed fixtures fail before execution. An unchanged fixture that
receives incorrect compiler output fails its original FileCheck expectations.

The gate requires a fresh JSON report containing exactly the six expected names,
each once, each `PASS`. Skipped, unsupported, expected-failure, missing or duplicate
results fail. Lit and FileCheck environment overrides are removed so filters,
shards or `--no-execute` cannot create a misleading pass.

The fork workflow runs the gate before the full suites and uploads its JSON and
logs. The gate uses the project's stdlib Python test convention and adds no package
dependency. It does not implement the semantic verifier in tracker #57, so it does
not complete all of #61's verifier/compatibility wiring.

## Updating a frozen baseline

A later behavior change requires explicit review of the affected test expectations.
Document why the change is intended, retain the test coverage, then update the
revision and relevant hashes in the manifest in the same reviewed change. Do not
automatically regenerate hashes to make a failing gate pass. A passing result
establishes these six fixtures; it does not establish complete CES coverage.
