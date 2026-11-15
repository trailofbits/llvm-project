Github action workflows should be stored in this directory.

The Trail of Bits fork runs `fork-ci.yml` on pull requests (including stacked PRs) and pushes to `enforced_secrecy_main`.
It builds LLVM, Clang, and MLIR with assertions and all standard LLVM targets; ClangIR is enabled.
It runs `check-llvm`, `check-clang` (including ClangIR), `check-clang-python`, and `check-mlir`
on a GitHub-hosted Ubuntu runner.
Shared LLVM/Clang libraries and a single concurrent link job reduce disk and memory use; the job has a six-hour timeout.
Configuration logs, build/test logs, and lit XML reports are uploaded even when a build or test fails.
The LLVM-only premerge jobs retain their upstream runner configuration.

Before the full suites, a dedicated
[register-zeroing compatibility gate](../../.ci/zeroization-compatibility.md) checks the six frozen
fixture hashes and requires all six tests to pass with the built compiler.
Its JSON results and build/test logs are included in the uploaded artifacts. The gate's unit tests
run before configuration. This is the compatibility part of tracker #60, not #57's semantic verifier.

The fork workflow does not require a CLA check.
`license/cla` is posted by an external integration, not by a workflow in this directory; disabling that status must be done in the integration's repository settings.
