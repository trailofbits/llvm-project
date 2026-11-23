# Native x86-64 residue probe

This is an execution test of one fixed-frame, void-return SysV function. It checks the 64 bytes of the source buffer, nine caller-saved GPRs, XMM0–XMM15, the six arithmetic flags, and three sampled callee-saved registers immediately after return. No caller C code or helper call runs before the assembly probe captures the state.

The function intentionally exports its local buffer address for the assembly observer. The observer copies those expired bytes in assembly; C does not dereference a pointer to an expired object. The flags push uses the expired incoming return-address slot, outside the buffer. The test runs at O0/O2 with and without a frame pointer.

An assembly positive control checks the observer. An unprotected compiler-built control must retain the buffer marker and nonzero vector state, and must fail the protected-state predicate. These controls prevent a probe that always reports zero or never inspects expired storage from passing.

Run on x86-64 Linux with a candidate Clang supporting zeroize_on_return and SAHF:

    bash .ci/check_zeroization_residue.sh /absolute/path/to/clang artifacts/residue

The fork CI retains each configuration's execution log, protected object and executable,
for example `O0-omit.log`, `protected-O0-omit.o` and `probe-O0-omit`.
The shared inputs remain `control.o` and `probe.o`. A probe-only build can link driver.c,
probe.S and an unprotected function.c object and run with --self-test.

This increment does not prove all owned padding/spill bytes, x87/MMX state, upper AVX lanes, every callee-save, exceptional exits, LVI, ARM or AArch64. It is a reproducible residue test for the listed state, not a whole-target completeness claim. The broader matrix remains tracked by internal issues 57–59.
