# ARM32 GNU cleanup execution check

The existing Linux all-target job uses its freshly built Clang and llc to
generate ARM and Thumb-2 cleanup code, then executes it with GNU's runtime under
`qemu-arm -cpu cortex-a15`. Ubuntu 24.04's
[`g++-arm-linux-gnueabihf`](https://packages.ubuntu.com/noble/g%2B%2B-arm-linux-gnueabihf)
supplies the cross compiler, binutils and
[target development libraries](https://packages.ubuntu.com/noble/arm64/devel/libstdc%2B%2B-13-dev-armhf-cross).
The existing `qemu-user` dependency supplies the emulator. No new LLVM build job
or modified runtime is required.

```sh
ulimit -c 0
python3 .ci/check_zeroization_arm32_cleanup.py \
  --clang "$PWD/build/bin/clang" --llc "$PWD/build/bin/llc" \
  --cxx /usr/bin/arm-linux-gnueabihf-g++ --nm /usr/bin/arm-linux-gnueabihf-nm \
  --qemu /usr/bin/qemu-arm --sysroot / \
  --source-revision "$(git rev-parse HEAD)" --output artifacts/arm32-cleanup
```

All tool and sysroot paths are explicit. The Ubuntu cross compiler locates its
target libraries below `/usr` with sysroot `/`; the executables are statically
linked. The header-free protected C++ is compiled by the candidate. GNU compiles
the independent observers and links its unmodified C++/EHABI runtime. R4 and R5
are reserved only in the observing code, which preserves the assembly caller's
R4/R5/D8 markers; the protected fixture does not reserve those registers.

## Bounded matrix

- **48 C++ source executions:** ARM and Thumb-2, protected and unprotected,
  four layouts, and normal/typed/forced exits with input 7. The layouts are the admitted
  8-byte minimum, a 32-byte frame, and 224-byte maximum frames with two and nine
  saved registers. These run at O1 without a frame pointer and with NEON enabled;
  they do not establish every optimization or calling-convention combination.
- **12 lowered-IR executions:** `two-exits.ll` explicitly contains two EH-lowered
  cleanup transfers. Tail merging is disabled for this fixture so both terminal
  transfers remain. Each ISA executes both branch inputs in all three modes.
  This is backend evidence, separately identified from the C++ source tests.
- **Two instrumented private-frame executions:** one per ISA, using the 32-byte
  source frame and a destructor that increments a counter. Assembly observers
  copy all 96 bytes at each generated personality's return, after its wipe and
  before releasing its allocation, without calls or stack writes. A guarded
  cleanup wrapper checks the original frame, incoming R4 and disjoint private
  storage. This instrumentation is test code, not a product runtime ABI.
- **Six omitted-wipe controls:** one original-frame omission per ISA, plus
  separate phase-personality and helper-personality omissions per ISA. They
  remove actual stores: original offset 4, phase-private offset 36 (containing
  the fixture's protected marker), and helper-private offset 92 (saved LR).
  The runner requires the intended residue observation and failure code; an
  ineffective mutation, unrelated crash or missing mutation match fails the gate.
- **Four compilation checks:** 232-byte protected requests must reject in both
  ISAs, while corresponding unprotected controls still compile.

Within the first 60 executions, 20 forced cases read the complete original
allocation: 12 protected observations require zero and eight unprotected
controls require nonzero residue. The 40 normal/typed cases check public results,
exception identity, destructor/branch behavior and caller state; they are not
additional byte-level observations. The two private cases separately observe
their original frames and both complete private allocations. Repeated callbacks
or omitted-store replays are not extra target coverage.

## Observation boundaries

Original frame size must agree between the generated MIR and the assembly's
single register push plus optional single fixed allocation. Unknown saves,
split SP adjustments and inconsistent unwind padding fail before execution.
The forced observer identifies `inner` using its actual object symbol extent.
It does not read unrelated frames merely because a cleanup callback occurred.
The private wrapper likewise checks its return address against the fixture's
dedicated code section before interpreting R4 as a carrier pointer.

Both generated private personalities must retain the reviewed nine-register
save plus 60-byte allocation, all 24 word clears and their immediate release/
return sequence. Changed bounds or an unrecognised sequence fail instrumentation
instead of silently measuring only part of a frame. Raw snapshots and cumulative
residue checks cover repeated private returns; the wrapper also checks that
private storage does not retain the fixture marker before its C callback.

The forced route follows the reviewed fixture's separate outer path; the typed
route uses the caller's catch. This suite does not include callback backtracing,
whose GNU limitation was also seen in the unprotected research control. It does
not establish general EHABI portability, arbitrary catch/filter personalities,
asynchronous unwinding, saved-VFP/frame-pointer layouts, non-local bypasses,
all register classes, hardware execution or milestone acceptance.

## Retained evidence and failure behavior

The output directory must be new. `inputs/` contains the runner and exact source
fixtures. Every configuration keeps its assembly, direct compiler object, MIR,
executable, symbol bound, command log and per-case output. Instrumented and
mutated assembly retain their own objects/executables. Tool versions and hashes,
GNU static library hashes, case identities and artifact hashes are recorded in
`results.json`, written only after all checks succeed.

The source revision is a declaration, not authenticated provenance. Keep the CI
checkout and build logs alongside these artifacts. A local replay using an older
compiler or replacement library must be labelled accordingly; it is not fresh
compiler CI. Each executable can be replayed using its exact command from the
named log and the recorded compatible QEMU/runtime tools.

Missing/duplicate success markers, incomplete snapshots, wrong residue, invalid
bounds, timeouts and incorrect mutation failures reject the run. The runner's
stdlib behavior tests execute before building LLVM:

```sh
python3 .ci/check_zeroization_arm32_cleanup_test.py
```
