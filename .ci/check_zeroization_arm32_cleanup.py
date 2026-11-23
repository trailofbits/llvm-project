"""Execute bounded ARM/Thumb-2 GNU C++ cleanup checks with the candidate compiler."""

import argparse
import hashlib
import json
import re
import shlex
import shutil
import subprocess
import sys
from pathlib import Path


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def execute(command: list[str], log: Path, *, expected: int = 0) -> str:
    """Run one bounded command, retaining its output and checking its exact status."""
    with log.open("a") as output:
        output.write(f"$ {shlex.join(command)}\n")
        output.flush()
        try:
            result = subprocess.run(
                command,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                timeout=30,
                check=False,
            )
        except subprocess.TimeoutExpired as error:
            partial = error.output or b""
            output.write(
                partial.decode(errors="replace") if isinstance(partial, bytes) else partial
            )
            output.write("\nTIMEOUT after 30 seconds\n")
            raise ValueError(f"Command timed out; see {log}") from error
        output.write(result.stdout)
        output.write(f"exit={result.returncode}\n")
    require(
        result.returncode == expected,
        f"Expected exit {expected}, got {result.returncode}; see {log}",
    )
    return result.stdout


def copy_inputs(output: Path) -> dict[str, str]:
    """Retain the runner and exact source bytes used to compile the fixtures."""
    source = Path(__file__).resolve()
    inputs = output / "inputs"
    inputs.mkdir()
    shutil.copy2(source, inputs / source.name)
    fixture = source.parent / "zeroization-arm32-cleanup"
    shutil.copytree(fixture, inputs / fixture.name)
    return {
        str(path.relative_to(output)): hashlib.sha256(path.read_bytes()).hexdigest()
        for path in sorted(inputs.rglob("*"))
        if path.is_file()
    }


def tool_metadata(args: argparse.Namespace) -> dict[str, object]:
    """Record explicit tools and GNU static runtime libraries for replay."""
    metadata = {}
    log = args.output / "tools.log"
    for name in ("clang", "llc", "cxx", "qemu", "nm"):
        path = getattr(args, name).absolute()
        require(path.is_file(), f"Missing {name} executable: {path}")
        setattr(args, name, path)
        metadata[name] = {
            "path": str(path),
            "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
            "version": execute([str(path), "--version"], log),
        }
    triple = execute([str(args.cxx), "-dumpmachine"], log).strip()
    require(
        triple == "arm-linux-gnueabihf",
        f"Expected GNU ARM C++ toolchain, got {triple}",
    )
    for name in ("libstdc++.a", "libgcc_eh.a", "libc.a"):
        value = execute(
            [str(args.cxx), f"--sysroot={args.sysroot}", f"-print-file-name={name}"],
            log,
        )
        path = Path(value.strip())
        require(path.is_file(), f"Missing static runtime {name}: {path}")
        metadata[name] = {
            "path": str(path),
            "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
        }
    return metadata


def function_body(assembly: str, name: str) -> str:
    """Require one complete assembly definition before inspecting fixture bounds."""
    bodies = re.findall(
        rf"^{re.escape(name)}:[^\n]*\n(.*?)^\s*\.size\s+{re.escape(name)},",
        assembly,
        re.MULTILINE | re.DOTALL,
    )
    require(len(bodies) == 1, f"Expected one complete definition of {name}")
    return bodies[0]


def frame_layout(assembly: str, mir: str) -> int:
    """Accept only the fixture's single push and optional single static allocation."""
    require(
        re.findall(r"^name:\s+(\S+)", mir, re.MULTILINE) == ["inner"],
        "Expected one MIR function named inner",
    )
    sizes = re.findall(r"^  stackSize:\s+(\d+)", mir, re.MULTILINE)
    require(len(sizes) == 1, "Ambiguous MIR frame extent")
    size = int(sizes[0])
    require(8 <= size <= 224 and size % 8 == 0, "Unsupported original frame extent")
    body = function_body(assembly, "inner")
    calls = re.split(r"^\s*blx?\s+", body, maxsplit=1, flags=re.MULTILINE)
    require(len(calls) == 2, "Missing first fixture call")
    prologue = calls[0]
    pushes = re.findall(r"^\s*push(?:\.w)?\s+\{([^}]+)\}", prologue, re.MULTILINE)
    saved = re.findall(r"^\s*\.save\s+\{([^}]+)\}", prologue, re.MULTILINE)
    require(len(pushes) == 1 and pushes == saved, "Ambiguous saved-register allocation")
    registers = [name.strip() for name in pushes[0].split(",")]
    allowed = [f"r{i}" for i in range(4, 12)] + ["lr"]
    require(
        registers == [name for name in allowed if name in registers],
        "Unexpected saved-register order or alias",
    )
    require(registers[0] == "r4" and registers[-1] == "lr", "Missing R4/LR save slots")
    adjustment = prologue_adjustment(prologue)
    require(len(registers) * 4 + adjustment == size, "Assembly/MIR frame extent mismatch")
    return size


def prologue_adjustment(prologue: str) -> int:
    """Reject unmodelled or split SP changes instead of guessing an observation bound."""
    writes = re.findall(r"^\s*\w+(?:\.w)?\s+sp\b[^\n]*", prologue, re.MULTILINE)
    allocations = re.findall(
        r"^\s*sub(?:\.w)?\s+sp,\s*(?:sp,\s*)?#(\d+)\s*$", prologue, re.MULTILINE
    )
    pads = re.findall(r"^\s*\.pad\s+#(\d+)", prologue, re.MULTILINE)
    require(len(writes) == len(allocations) <= 1, "Unsupported prologue SP adjustment")
    require(allocations == pads, "SP allocation disagrees with unwind padding")
    require(
        re.search(r"vpush|vpop|\.vsave|\[sp[^\n]*\]!|\{[^}\n]*\bsp\b", prologue) is None,
        "Unsupported prologue save or writeback",
    )
    return int(allocations[0]) if allocations else 0


def omit_original_wipe(assembly: str) -> str:
    """Remove one actual word clear in the protected source fixture's cleanup."""
    body = function_body(assembly, "inner")
    changed, count = re.subn(
        r"^\s*str(?:\.w)?\s+r3,\s*\[r0, #4\]\s*$",
        "\tnop @ Deliberately omit an original-frame clear",
        body,
        flags=re.MULTILINE,
    )
    require(count == 1, "Expected exactly one original-frame wipe mutation")
    return assembly.replace(body, changed, 1)


def private_capture(index: int) -> str:
    """Record all 96 bytes without a call or stack write, then re-clear temporaries."""
    text = [
        "\tldr r12,=private_observations",
        f"\tadd r12,r12,#{112 * index}",
        "\tstr sp,[r12]",
        "\tldr r1,[r12,#4]",
        "\tadd r1,r1,#1",
        "\tstr r1,[r12,#4]",
        "\tldr r3,[r12,#8]",
    ]
    for offset in range(0, 96, 4):
        text.extend(
            [f"\tldr r1,[sp,#{offset}]", f"\tstr r1,[r12,#{offset + 12}]", "\torr r3,r3,r1"]
        )
    text.extend(
        [
            "\tstr r3,[r12,#8]",
            "\tmov r1,#0",
            "\tmov r2,#0",
            "\tmov r3,#0",
            "\tmov r12,#0",
            "\tmsr APSR_nzcvq,r1",
        ]
    )
    return "\n".join(text) + "\n"


def private_layout(body: str) -> None:
    """Require the reviewed nine-register save plus 60-byte private allocation."""
    calls = re.split(r"^\s*blx?\s+", body, maxsplit=1, flags=re.MULTILINE)
    require(len(calls) == 2, "Missing private runtime call")
    prologue = calls[0]
    pushes = re.findall(r"^\s*push\s+\{([^}]+)\}", prologue, re.MULTILINE)
    saved = re.findall(r"^\s*\.save\s+\{([^}]+)\}", prologue, re.MULTILINE)
    registers = ", ".join([f"r{i}" for i in range(4, 12)] + ["lr"])
    require(pushes == saved == [registers], "Unsupported private saved-register layout")
    require(prologue_adjustment(prologue) == 60, "Unsupported private allocation extent")


def instrument_private(assembly: str, omitted: int | None) -> str:
    """Observe both generated personalities; optionally omit one real word store."""
    for index, name in enumerate(("personality", "helper_personality")):
        symbol = f".Larm_zeroize_{name}_0"
        body = function_body(assembly, symbol)
        private_layout(body)
        restores = list(re.finditer(r"^\s*ldm\s+r12,", body, re.MULTILINE))
        require(len(restores) == 1, "Ambiguous private return restore")
        start = restores[0].start()
        tail = body[start:]
        require(
            re.search(r"\badd\s+sp, sp, #96\n\s*bx\s+lr\n\s*\.fnend\n(?:\.Ltmp\d+:\n)?$", tail)
            is not None,
            "Unsupported instructions after private-frame release",
        )
        stores = re.findall(r"^\s*str\s+r1,\s*\[sp(?:, #(\d+))?\]\s*$", tail, re.MULTILINE)
        require(
            [int(value or 0) for value in stores] == list(range(0, 96, 4)),
            "Expected the complete 96-byte private wipe",
        )
        if omitted == index:
            offset = 36 if index == 0 else 92
            tail, count = re.subn(
                rf"^\s*str\s+r1,\s*\[sp, #{offset}\]\s*$",
                "\tnop @ Deliberately omit one private-frame clear",
                tail,
                flags=re.MULTILINE,
            )
            require(count == 1, "Private wipe mutation did not remove exactly one store")
        tail, count = re.subn(
            r"^\s*add\s+sp, sp, #96\s*$",
            private_capture(index) + "\tadd sp, sp, #96",
            tail,
            flags=re.MULTILINE,
        )
        require(count == 1, "Expected one private frame release")
        assembly = assembly.replace(body, body[:start] + tail, 1)
    return (
        assembly + "\n.bss\n.p2align 2\n.global private_observations\n"
        "private_observations:\n.space 224\n"
    )


def observed_frame(text: str, size: int) -> bytes:
    """Require one complete raw frame snapshot before considering its contents."""
    frames = re.findall(r"^FRAME bytes=(\d+) hex=([0-9a-f]+)$", text, re.MULTILINE)
    require(len(frames) == 1, "Missing or repeated original-frame observation")
    require(int(frames[0][0]) == size, "Wrong original-frame extent")
    data = bytes.fromhex(frames[0][1])
    require(len(data) == size, "Truncated original-frame observation")
    return data


def check_observation(text: str, *, mode: str, variant: str, size: int) -> None:
    """Distinguish behavior-only successes from actual protected/control frame reads."""
    require(text.count(f"PASS mode={mode}\n") == 1, "Missing or repeated success marker")
    require("FAIL reason=" not in text, "Observer reported a failure")
    if mode == "forced":
        require(
            any(observed_frame(text, size)) == (variant == "control"),
            "Wrong original-frame residue",
        )


def check_private(text: str, omitted: int | None) -> None:
    """Require both bounded private snapshots and the intended omission failure."""
    require(not any(observed_frame(text, 32)), "Private probe retained original-frame residue")
    matches = re.findall(
        r"^PRIVATE index=(\d+) bytes=96 hex=([0-9a-f]+) returns=(\d+) OR=([0-9a-f]+)$",
        text,
        re.MULTILINE,
    )
    require([int(row[0]) for row in matches] == [0, 1], "Missing or repeated private observation")
    for index, hexdata, returns, residue in matches:
        data = bytes.fromhex(hexdata)
        require(len(data) == 96 and int(returns) > 0, "Truncated or unexecuted private observation")
        dirty = int(index) == omitted
        require(
            any(data) == dirty and bool(int(residue, 16)) == dirty, "Wrong private-frame residue"
        )
    if omitted is None:
        check_observation(text, mode="private", variant="protected", size=32)
    else:
        require(
            text.count("FAIL reason=private-residue\n") == 1,
            "Private mutation failed for an unrelated reason",
        )
        require("PASS mode=" not in text, "Mutation unexpectedly reported success")


def clang_flags(args: argparse.Namespace, isa: str) -> list[str]:
    return [
        str(args.clang),
        "--driver-mode=g++",
        "--target=armv7-linux-gnueabihf",
        f"--sysroot={args.sysroot}",
        "-march=armv7-a",
        f"-m{isa}",
        "-mfpu=neon",
        "-O1",
        "-fomit-frame-pointer",
        "-fno-addrsig",
        "-Wall",
        "-Wextra",
        "-Werror",
        "-mllvm",
        "-verify-machineinstrs",
    ]


def compile_source(args: argparse.Namespace, stem: str, isa: str, definitions: list[str]) -> int:
    """Keep actual compiler objects plus matching assembly/MIR for bounded inspection."""
    flags = [*clang_flags(args, isa), *definitions, str(args.inputs / "inner.cpp")]
    for suffix, mode in (
        ("s", ["-S"]),
        ("o", ["-c"]),
        ("mir", ["-S", "-mllvm", "-stop-after=arm-cp-islands"]),
    ):
        execute(
            [*flags, *mode, "-o", str(args.output / f"{stem}.{suffix}")], args.output / "build.log"
        )
    return frame_layout(
        (args.output / f"{stem}.s").read_text(), (args.output / f"{stem}.mir").read_text()
    )


def build_observers(args: argparse.Namespace) -> None:
    """Compile the independent GNU observers and register-marker caller."""
    flags = [
        str(args.cxx),
        f"--sysroot={args.sysroot}",
        "-marm",
        "-mfpu=neon",
        "-O0",
        "-funwind-tables",
        "-fno-omit-frame-pointer",
        "-ffixed-r4",
        "-ffixed-r5",
        "-Wall",
        "-Wextra",
        "-Werror",
    ]
    for name in ("observer.cpp", "private-observer.cpp", "markers.S", "private-boundary.S"):
        execute(
            [
                *flags,
                "-c",
                str(args.inputs / name),
                "-o",
                str(args.output / (Path(name).stem + ".o")),
            ],
            args.output / "build.log",
        )


def assemble(args: argparse.Namespace, stem: str) -> None:
    execute(
        [
            str(args.cxx),
            f"--sysroot={args.sysroot}",
            "-marm",
            "-mfpu=neon",
            "-c",
            str(args.output / f"{stem}.s"),
            "-o",
            str(args.output / f"{stem}.o"),
        ],
        args.output / "build.log",
    )


def link_fixture(args: argparse.Namespace, stem: str, *, private: bool = False) -> Path:
    """Keep each static executable beside the exact object it uses."""
    objects = [f"{stem}.o", "private-observer.o" if private else "observer.o", "markers.o"]
    options = []
    if private:
        objects.append("private-boundary.o")
        options.append("-Wl,--wrap=__cxa_end_cleanup")
    binary = args.output / f"{stem}.elf"
    execute(
        [
            str(args.cxx),
            f"--sysroot={args.sysroot}",
            "-static",
            "-marm",
            *[str(args.output / obj) for obj in objects],
            *options,
            "-o",
            str(binary),
        ],
        args.output / "build.log",
    )
    return binary


def inner_size(args: argparse.Namespace, stem: str) -> int:
    """Get the complete original-function code bound without including its local helpers."""
    text = execute(
        [str(args.nm), "-S", "--defined-only", str(args.output / f"{stem}.o")],
        args.output / f"{stem}-symbols.log",
    )
    sizes = re.findall(r"^[0-9a-fA-F]+\s+([0-9a-fA-F]+)\s+[Tt]\s+inner$", text, re.MULTILINE)
    require(len(sizes) == 1, "Ambiguous inner symbol extent")
    size = int(sizes[0], 16)
    require(0 < size <= 65536, "Unsupported inner code bound")
    return size


def runtime_case(
    args: argparse.Namespace,
    binary: Path,
    size: int,
    *,
    variant: str,
    mode: str,
    value: int = 7,
    distinct: bool = False,
    mutation: bool = False,
) -> dict[str, object]:
    """Require the exact exit status and observation for one retained executable."""
    log = args.output / f"{binary.stem}-{mode}-{value}.log"
    text = execute(
        [
            str(args.qemu),
            "-cpu",
            "cortex-a15",
            str(binary),
            variant,
            mode,
            str(size),
            str(inner_size(args, binary.stem)),
            str(value),
            "distinct" if distinct else "source",
        ],
        log,
        expected=78 if mutation else 0,
    )
    if mutation:
        require(any(observed_frame(text, size)), "Omitted original wipe did not leave residue")
        require(
            text.count("FAIL reason=original-residue\n") == 1,
            "Original wipe mutation failed for an unrelated reason",
        )
        require("PASS mode=" not in text, "Mutation unexpectedly reported success")
    else:
        check_observation(text, mode=mode, variant=variant, size=size)
    return {
        "binary": binary.name,
        "variant": variant,
        "mode": mode,
        "input": value,
        "frame_size": size,
        "distinct_lowered_IR": distinct,
        "mutation": mutation,
        "log": log.name,
        "passed": True,
    }


def source_matrix(args: argparse.Namespace) -> list[dict[str, object]]:
    """Cover admitted frame boundaries and ordinary two-/nine-register save recipes."""
    layouts = {
        "minimum": (8, ["-DMINIMUM"]),
        "small": (32, []),
        "maximum": (224, ["-DWORDS=54"]),
        "saved": (224, ["-DWORDS=46", "-DSAVE_ALL"]),
    }
    rows = []
    for isa in ("arm", "thumb"):
        for name, (expected, definitions) in layouts.items():
            for variant in ("protected", "control"):
                stem = f"{name}-{isa}-{variant}"
                flags = definitions + (["-DPROTECTED"] if variant == "protected" else [])
                size = compile_source(args, stem, isa, flags)
                require(size == expected, f"Unexpected {stem} frame size")
                binary = link_fixture(args, stem)
                rows.extend(
                    runtime_case(args, binary, size, variant=variant, mode=mode)
                    for mode in ("normal", "typed", "forced")
                )
    return rows


def distinct_matrix(args: argparse.Namespace) -> list[dict[str, object]]:
    """Exercise two actual cleanup sites from explicitly EH-lowered IR."""
    rows = []
    for isa in ("arm", "thumb"):
        stem = f"two-exits-{isa}"
        flags = [
            str(args.llc),
            f"-mtriple={isa}v7-linux-gnueabihf",
            "-mattr=+neon",
            "-enable-tail-merge=false",
            "-disable-cgp",
            "-verify-machineinstrs",
            str(args.inputs / "two-exits.ll"),
        ]
        for suffix, mode in (
            ("s", "-filetype=asm"),
            ("o", "-filetype=obj"),
            ("mir", "-stop-after=arm-cp-islands"),
        ):
            execute(
                [*flags, mode, "-o", str(args.output / f"{stem}.{suffix}")],
                args.output / "build.log",
            )
        assembly = (args.output / f"{stem}.s").read_text()
        require(
            len(re.findall(r"^\s*bx\s+r12\s*$", function_body(assembly, "inner"), re.MULTILINE))
            == 2,
            "Expected two distinct cleanup transfers",
        )
        size = frame_layout(assembly, (args.output / f"{stem}.mir").read_text())
        binary = link_fixture(args, stem)
        for mode in ("normal", "typed", "forced"):
            rows.extend(
                runtime_case(
                    args, binary, size, variant="protected", mode=mode, value=value, distinct=True
                )
                for value in (7, 8)
            )
    return rows


def mutation_matrix(args: argparse.Namespace) -> list[dict[str, object]]:
    """Require genuine original/private omitted-store failures, not arbitrary crashes."""
    rows = []
    for isa in ("arm", "thumb"):
        stem = f"missing-original-{isa}"
        source = (args.output / f"small-{isa}-protected.s").read_text()
        (args.output / f"{stem}.s").write_text(omit_original_wipe(source))
        assemble(args, stem)
        binary = link_fixture(args, stem)
        rows.append(
            runtime_case(args, binary, 32, variant="protected", mode="forced", mutation=True)
        )
        original = f"private-source-{isa}"
        size = compile_source(args, original, isa, ["-DPROTECTED", "-DPRIVATE_OBSERVATION"])
        require(size == 32, "Unsupported private-observer original extent")
        assembly = (args.output / f"{original}.s").read_text()
        for omitted in (None, 0, 1):
            rows.append(private_case(args, assembly, isa, omitted=omitted))
    return rows


def private_case(
    args: argparse.Namespace, assembly: str, isa: str, *, omitted: int | None
) -> dict[str, object]:
    stem = f"private-{isa}-" + ("cleared" if omitted is None else f"missing-{omitted}")
    (args.output / f"{stem}.s").write_text(instrument_private(assembly, omitted))
    assemble(args, stem)
    binary = link_fixture(args, stem, private=True)
    log = args.output / f"{stem}.log"
    text = execute(
        [str(args.qemu), "-cpu", "cortex-a15", str(binary), "32"],
        log,
        expected=0 if omitted is None else 79,
    )
    check_private(text, omitted)
    return {
        "binary": binary.name,
        "mode": "private",
        "omitted_personality": omitted,
        "omitted_offset": None if omitted is None else (36 if omitted == 0 else 92),
        "original_frame_size": 32,
        "private_frame_size": 96,
        "log": log.name,
        "passed": True,
    }


def reject_oversized(args: argparse.Namespace) -> None:
    """Keep the 224-byte capability boundary explicit; a larger control still compiles."""
    for isa in ("arm", "thumb"):
        flags = [*clang_flags(args, isa), "-DWORDS=56", "-S", str(args.inputs / "inner.cpp")]
        text = execute(
            [*flags, "-DPROTECTED", "-o", str(args.output / f"rejected-{isa}.s")],
            args.output / f"rejected-{isa}.log",
            expected=1,
        )
        require(
            "ARM cleanup clearing requires the supported SP-based frame recipe" in text,
            "Missing oversized-frame diagnostic",
        )
        execute(
            [*flags, "-o", str(args.output / f"large-control-{isa}.s")], args.output / "build.log"
        )


def main() -> int:
    """Collect bounded execution evidence for an explicitly identified compiler build."""
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("clang", "llc", "cxx", "qemu", "nm", "sysroot", "output"):
        parser.add_argument(f"--{name}", type=Path, required=True)
    parser.add_argument("--source-revision", required=True)
    args = parser.parse_args()
    require(
        re.fullmatch(r"[0-9a-f]{40}", args.source_revision) is not None,
        "Expected full source revision",
    )
    args.sysroot = args.sysroot.resolve(strict=True)
    require(args.sysroot.is_dir(), "Sysroot must be a directory")
    args.output = args.output.resolve()
    args.output.mkdir(parents=True, exist_ok=False)
    inputs = copy_inputs(args.output)
    args.inputs = args.output / "inputs" / "zeroization-arm32-cleanup"
    tools = tool_metadata(args)
    build_observers(args)
    rows = source_matrix(args) + distinct_matrix(args) + mutation_matrix(args)
    reject_oversized(args)
    require(len(rows) == 68, "Expected 48 source cases, 12 lowered-IR cases and eight wipe probes")
    artifacts = {
        str(path.relative_to(args.output)): hashlib.sha256(path.read_bytes()).hexdigest()
        for path in sorted(args.output.rglob("*"))
        if path.is_file()
    }
    report = {
        "success": True,
        "source_revision": args.source_revision,
        "sysroot": str(args.sysroot),
        "tools": tools,
        "inputs": inputs,
        "observations": rows,
        "artifacts": artifacts,
        "oversized_frame": "rejected for ARM/Thumb; unprotected controls compiled",
    }
    (args.output / "results.json").write_text(json.dumps(report, indent=2) + "\n")
    print("PASS: 60 ARM32 behavior cases, two private observations and six detected wipe omissions")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError) as error:
        sys.exit(str(error))
