# SVE first-fault register runtime check

`check_zeroization_ffr.py` compiles two fixtures with the supplied compiler,
assembles them with Clang, and cross-links static AArch64 Linux executables with
LLD. QEMU user emulation runs each executable and the assembly observer snapshots
registers immediately after the protected function returns, before any calls or
syscalls. No target sysroot or C library is needed.

From the repository root, after building `llc` and Clang with AArch64 support:

```sh
python3 .ci/check_zeroization_ffr_test.py
python3 .ci/check_zeroization_ffr.py \
  --llc "$PWD/build/bin/llc" --clang "$PWD/build/bin/clang" \
  --linker /usr/bin/ld.lld --qemu /usr/bin/qemu-aarch64 \
  --output artifacts/sve-ffr
```

The output directory must be new; an existing directory is rejected to prevent
stale evidence from contributing to a pass. The Linux fork workflow installs
Ubuntu's `lld` and `qemu-user` packages and runs this command using the compiler
just built from its checkout. Ubuntu 24.04's QEMU 8.2.2 was used when developing
this check. QEMU's documented
[`sve-default-vector-length`](https://www.qemu.org/docs/master/system/arm/cpu-features.html#sve-user-mode-default-vector-length-property)
property specifies bytes. The observer's `CNTB` result must match the requested
length, so silently reduced vector lengths cannot pass.

## Matrix and controls

There are 144 executed cases:

- Register modes `all` and `used`.
- Base AAPCS64 and SVE vector calling conventions.
- Optimization levels `-O0` and `-O2`.
- Vector lengths 16, 64, and 256 bytes.
- Two invocation selectors.
- Protected, unprotected, and deliberately missing-FFR-clear variants.

The 48 protected cases require every active FFR bit to be zero. The 96 controls
require every FFR bit to retain the nonzero seed. Both controls use the current
compiler; there is no dependency on an old checkout. The missing-clear variant
removes actual `WRFFR` instructions from the protected assembly, verifies that
there was one per fixture return, and rejects an ineffective or partial mutation.
The unprotected variant removes the fixture's clearing attributes.

`all.ll` includes two source exits in the vector function and checks its vector
result. `used.ll` explicitly uses FFR and returns a full predicate, which must
survive scratch selection. Both contain a real call and fixed local storage.
The observer seeds preserved vectors and predicates and the checker verifies
those values, the scalar result, the stack pointer, and FFR for every variant.
For protected and mutated `all` cases, it also checks the covered ordinary
registers, upper vector lanes, predicates, and NZCV.

## Evidence and scope

Before invoking any tools, the runner saves its exact bytes and all three
fixtures under `inputs/`, preserving the `zeroization-ffr/` source layout. It
compiles those saved fixtures. The output also contains raw snapshots,
assembly, objects, executables, exact tool commands and diagnostics, tool
versions, and `results.json`. That report is written only after every case
succeeds and contains one row per observation,
tool executable hashes, and fixture/runner hashes. A tool error, timeout,
truncated snapshot, unexpected length, changed interface value, or incorrect
FFR state fails the run. The workflow uploads the directory with its other
artifacts even when a later step fails. To reproduce a downloaded artifact,
run `python3 inputs/check_zeroization_ffr.py` with the same tool arguments and
a new output directory; a repository checkout is not needed.

Each snapshot is 200 header bytes followed by 32 vector registers, 16 predicate
registers, and FFR. For vector length `VL`, FFR starts at
`200 + 32*VL + 16*(VL/8)` and occupies `VL/8` bytes. The final predicate scratch
used to read FFR is overwritten only after the other predicates are saved.

These checks exercise normal SVE returns and known nonzero state under QEMU.
They do not establish hardware behavior, every return protocol, speculative
execution guarantees, or full milestone acceptance. Streaming legality and
scratch-exhaustion diagnostics have separate compiler regressions.
