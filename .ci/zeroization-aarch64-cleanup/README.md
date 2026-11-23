# AArch64 C++ cleanup execution check

This fixture uses the freshly built compiler to generate protected and
unprotected C++, then runs statically linked GNU C++ programs with `qemu-aarch64`.
The existing Linux all-target CI job installs Ubuntu 24.04's
[`g++-aarch64-linux-gnu`](https://packages.ubuntu.com/en/noble/amd64/g%2B%2B-aarch64-linux-gnu)
and `qemu-user`. The cross compiler's dependencies supply the
[AArch64 C++ and libc development libraries](https://packages.ubuntu.com/en/noble/libstdc%2B%2B-13-dev-arm64-cross).
No additional LLVM build or modified unwinder is used.

```sh
ulimit -c 0
python3 .ci/check_zeroization_aarch64_cleanup.py \
  --clang "$PWD/build/bin/clang" --cxx /usr/bin/aarch64-linux-gnu-g++ \
  --qemu /usr/bin/qemu-aarch64 --sysroot / \
  --source-revision "$(git rev-parse HEAD)" --output artifacts/aarch64-cleanup
```

Tool paths and the GNU toolchain sysroot are explicit. The Ubuntu cross compiler
finds its target libraries below `/usr` with sysroot `/`; static executables do
not need a guest dynamic-loader prefix. The protected C++ fixture has no headers.
The GNU compiler builds the observing driver independently, using reserved
marker registers; these options do not reserve registers in the protected callee.

## What executes

- At O0 and O2, protected and unprotected functions each run with two inputs in
  four modes: normal return, locally caught exception, typed exception caught
  by the caller, and forced unwinding. These are 32 runtime cases.
- Eight of those cases observe the original frame during forced cleanup: four
  protected cases require all original bytes to be zero; four unprotected
  controls require nonzero residue. The generated prologue allocation must
  match its initial CFI extent before the observer reads that many bytes.
- Protected forced cases also check original frame identity, the separate
  32-byte helper allocation, restored X19/X20, inherited X21 and saved LR, and
  the continuation matching the observed unwind PC. Destructor order and the
  caller's X19/X20/X21/D8 markers are checked through the actual unwinder.
- Four additional forced executions use generated assembly with its real X21
  reloads removed. The runner requires the specific caller-X21 observation
  failure, rather than accepting any crash or nonzero exit. A missing mutation
  match is an error.
- Three compilation checks reject reserved-X21 protected escaping cleanup and
  keep unprotected cleanup and protected ordinary-return controls accepted.
  The committed compiler tests separately cover reserved X1 and other unsupported
  configurations.

Only the forced cases observe frame bytes. Normal and typed/caught cases check
public behavior and ABI preservation; they are not extra byte-level residue
measurements. This covers one fixed-frame GNU personality fixture, not every
exit, register class, unwinder, nesting depth or hardware configuration. QEMU
execution does not establish native-hardware coverage or milestone acceptance.

## Evidence and failure behavior

The output directory must be new. It retains exact sources and runner in
`inputs/`, generated assembly, objects, static executables, raw per-case logs,
build commands, tool/runtime-library versions and hashes, and mutation counts.
`results.json` is written only after every case and diagnostic check succeeds;
it includes individual outcomes and hashes of retained artifacts. The source
revision is the collector's declaration, not authenticated provenance. Retain
the CI checkout/build logs alongside this directory to establish how the
compiler was built.

The driver prints the raw observed frame and helper values before checking them.
Missing success markers, incorrect frame lengths, timeouts, unexpected statuses,
and mutations failing for the wrong reason all fail the runner. Its standard-
library behavior tests run before the compiler build:

```sh
python3 .ci/check_zeroization_aarch64_cleanup_test.py
```
