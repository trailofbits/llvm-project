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

## Mixed handlers and uninstrumented helper returns

The same gate also runs:

- **216 mixed-handler executions:** ARM/Thumb-2, protected/control, typed and
  catch-all profiles, three layouts, and nine scenarios. The catch-all body
  retains the published `WITH_CATCH` shape: `try { action(0); } catch (...) {
  action(1); }`. Cases cover normal return, caught return, rethrow, replacement,
  nonmatching types, forced unwinding, a second typed selector, and three nested
  reentries that either return or escape. Each profile uses its small frame
  (40 bytes typed, 32 bytes catch-all), a 224-byte maximum, and a 224-byte frame
  saving all nine supported GPRs. Nested cases execute four protected functions;
  they are not four independent scenario counts.
- **Eight terminate-control executions:** protected/control, two ISAs, and
  ordinary versus destructor-throws-during-unwind paths. These preserve the
  generated terminate handler's behavior. They do not observe erasure at
  process termination.
- **Two raw helper executions:** one per ISA, with 62 controlled API/success/error
  cases each. They export aliases for the actual emitted personalities and add
  no memory observer or clearing instructions. The assembly caller checks
  restored R4-R11 and cleared R1-R3/R12/NZCVQ immediately after return. Positive
  selectors 1 and 2 must retain INSTALL_CONTEXT and the selected virtual state;
  negative selectors fail. These checks make no private-memory observation.
- **Ten raw mutation controls:** independently omit the R2 or NZCVQ clear in each
  personality, plus remove the positive-handler pass-through, for both ISAs.
  The gate requires the specific incorrect physical state or handler result,
  not merely a nonzero exit. A phase-personality failure cannot mask the
  helper-personality omission.

The mixed fixture observes the entire original allocation only at actual
escaping cleanup transfers, with a wrapper restricted to its code section.
Normal/local-catch cases check behavior and caller state, not residual stack
bytes after an ordinary return. The 16-byte carrier contains incoming interface
context and is separate from both the original frame and the two private
96-byte allocations; these checks do not claim its post-use erasure.

Private-memory instrumentation necessarily restores its own temporary registers
and flags. Its results establish the complete private-memory wipe, while the
separate raw checks above establish the production helper's physical-register
behavior. Do not attribute the observer's register clears to the compiler.

The maintained gate uses GNU. Separate research replay found LLVM 18 and the
pinned LLVM runtime abort on forced unwinding rethrown through a catch-all in
both protected and unprotected controls. That matched runtime limitation is not
counted as a successful case or evidence of general EHABI portability.

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
not establish general EHABI portability, arbitrary personalities or exception filters,
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
