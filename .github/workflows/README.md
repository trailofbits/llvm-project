Github action workflows should be stored in this directory.

The Trail of Bits fork runs `fork-ci.yml` on pull requests (including stacked PRs) and pushes to `enforced_secrecy_main`.
It builds LLVM and Clang with assertions and all standard LLVM targets, then runs the complete `check-llvm`, `check-clang`, and `check-clang-python` suites on a GitHub-hosted Ubuntu runner.
Shared LLVM/Clang libraries and a single concurrent link job reduce disk and memory use; the job has a six-hour timeout.
Configuration logs, build/test logs, and lit XML reports are uploaded even when a build or test fails.
The LLVM-only premerge jobs retain their upstream runner configuration.

The fork workflow does not require a CLA check.
`license/cla` is posted by an external integration, not by a workflow in this directory; disabling that status must be done in the integration's repository settings.
