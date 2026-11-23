"""Observe generated AArch64 C++ cleanups under QEMU with the GNU unwinder."""

import argparse
import hashlib
import itertools
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
                partial.decode(errors="replace")
                if isinstance(partial, bytes)
                else partial
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
    fixture = source.parent / "zeroization-aarch64-cleanup"
    shutil.copytree(fixture, inputs / fixture.name)
    return {
        str(path.relative_to(output)): hashlib.sha256(path.read_bytes()).hexdigest()
        for path in sorted(inputs.rglob("*"))
        if path.is_file()
    }


def frame_layout(assembly: str) -> tuple[int, int]:
    """Cross-check the fixed prologue allocation and its saved-LR unwind rule."""
    body = re.search(
        r"^inner:.*?\n(.*?)^\s*\.size\s+inner\b", assembly, re.MULTILINE | re.DOTALL
    )
    require(body is not None, "Missing generated inner function extent")
    assert body is not None
    cfa = re.search(r"\.cfi_def_cfa_offset\s+(\d+)", body[1])
    require(cfa is not None, "Missing initial frame allocation CFI")
    assert cfa is not None
    size = int(cfa[1])
    allocations = re.findall(
        r"\bsub\s+sp,\s*sp,\s*#(\d+)|\[sp,\s*#-(\d+)\]!", body[1][: cfa.start()]
    )
    require(len(allocations) == 1, "Expected one fixed prologue allocation")
    require(
        int(allocations[0][0] or allocations[0][1]) == size, "SP/CFI extent mismatch"
    )
    require(0 < size <= 4096 and size % 16 == 0, "Unsupported fixture frame size")
    lr = re.search(r"\.cfi_offset\s+[wx]30,\s*-(\d+)", body[1])
    require(lr is not None, "Missing saved-LR unwind rule")
    assert lr is not None
    offset = size - int(lr[1])
    require(0 <= offset <= size - 8 and offset % 8 == 0, "Invalid saved-LR offset")
    return size, offset


def omit_x21_restore(assembly: str) -> tuple[str, int]:
    """Omit real X21 reloads, failing if the generated fixture no longer has them."""
    text, count = re.subn(
        r"^\s*ldr\s+x21,\s*\[[^\]\n]+\]\s*(?://[^\n]*)?$",
        "\tnop // Deliberately omit the caller X21 restore",
        assembly,
        flags=re.MULTILINE,
    )
    require(
        count > 0, "Mutation did not find any X21 restore; inspect generated assembly"
    )
    return text, count


def check_observation(text: str, *, variant: str, mode: str, size: int) -> None:
    """Require an executed observation, not only a zero process exit code."""
    require(
        text.count(f"PASS mode={mode}\n") == 1, "Missing or repeated success marker"
    )
    require("FAIL reason=" not in text, "Observer reported a failure")
    if mode != "forced":
        return
    frames = re.findall(r"^FRAME bytes=(\d+) hex=([0-9a-f]+)$", text, re.MULTILINE)
    require(len(frames) == 1, "Expected one raw original-frame observation")
    require(
        int(frames[0][0]) == size, "Observed frame size differs from generated frame"
    )
    data = bytes.fromhex(frames[0][1])
    require(len(data) == size, "Truncated original-frame snapshot")
    require(any(data) == (variant == "control"), "Unexpected original-frame residue")
    if variant == "protected":
        require(
            "CONTEXT restored=1 helper-disjoint=1\n" in text,
            "Missing helper/context check",
        )


def tool_metadata(args: argparse.Namespace) -> dict[str, object]:
    """Record explicit tools and GNU static runtime libraries for replay."""
    metadata = {}
    log = args.output / "tools.log"
    for name in ("clang", "cxx", "qemu"):
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
        triple == "aarch64-linux-gnu",
        f"Expected GNU AArch64 C++ toolchain, got {triple}",
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


def compile_fixture(
    args: argparse.Namespace, output: Path, flags: list[str], *, expected: int = 0
) -> str:
    """Compile header-free C++ using the compiler under test."""
    return execute(
        [
            str(args.clang),
            "--driver-mode=g++",
            "--target=aarch64-linux-gnu",
            f"--sysroot={args.sysroot}",
            "-fno-omit-frame-pointer",
            "-Wall",
            "-Wextra",
            "-Werror",
            "-mllvm",
            "-verify-machineinstrs",
            *flags,
            "-S",
            str(args.inputs / "inner.cpp"),
            "-o",
            str(output),
        ],
        args.output / "build.log",
        expected=expected,
    )


def build_observer(args: argparse.Namespace) -> None:
    """Build the independent GNU observer and ABI marker caller."""
    execute(
        [
            str(args.cxx),
            f"--sysroot={args.sysroot}",
            "-O0",
            "-fno-omit-frame-pointer",
            "-ffixed-x19",
            "-ffixed-x20",
            "-ffixed-x21",
            "-ffixed-v8",
            "-Wall",
            "-Wextra",
            "-Werror",
            "-c",
            str(args.inputs / "observer.cpp"),
            "-o",
            str(args.output / "observer.o"),
        ],
        args.output / "build.log",
    )
    execute(
        [
            str(args.clang),
            "--target=aarch64-linux-gnu",
            "-c",
            str(args.inputs / "markers.S"),
            "-o",
            str(args.output / "markers.o"),
        ],
        args.output / "build.log",
    )


def link_fixture(args: argparse.Namespace, assembly: Path) -> Path:
    """Keep the generated object and its statically linked executable."""
    obj = assembly.with_suffix(".o")
    binary = assembly.with_suffix(".elf")
    execute(
        [
            str(args.clang),
            "--target=aarch64-linux-gnu",
            "-c",
            str(assembly),
            "-o",
            str(obj),
        ],
        args.output / "build.log",
    )
    execute(
        [
            str(args.cxx),
            f"--sysroot={args.sysroot}",
            "-static",
            str(args.output / "observer.o"),
            str(obj),
            str(args.output / "markers.o"),
            "-Wl,--eh-frame-hdr",
            "-o",
            str(binary),
        ],
        args.output / "build.log",
    )
    return binary


def runtime_case(
    args: argparse.Namespace,
    binary: Path,
    layout: tuple[int, int],
    *,
    variant: str,
    mode: str,
    value: int,
    mutated: bool = False,
) -> dict[str, object]:
    """Observe one generated fixture, requiring the intended mutation failure."""
    size, offset = layout
    log = args.output / f"{binary.stem}-{mode}-{value}.log"
    text = execute(
        [
            str(args.qemu),
            str(binary),
            variant,
            mode,
            str(size),
            str(offset),
            str(value),
        ],
        log,
        expected=76 if mutated else 0,
    )
    if mutated:
        require(
            "FAIL reason=caller-x21\n" in text,
            "Mutation failed for an unrelated reason",
        )
    else:
        check_observation(text, variant=variant, mode=mode, size=size)
    return {
        "binary": binary.name,
        "variant": variant,
        "mode": mode,
        "input": value,
        "frame_size": size,
        "saved_lr_offset": offset,
        "mutated": mutated,
        "log": log.name,
        "passed": True,
    }


def check_reserved(args: argparse.Namespace) -> None:
    """Require reserved-X21 rejection while keeping the corresponding controls valid."""
    flags = ["-O2", "-ffixed-x21", "-DRESERVE_X21"]
    text = compile_fixture(
        args, args.output / "reserved-protected.s", [*flags, "-DPROTECTED"], expected=1
    )
    require(
        "AArch64 stack clearing does not support" in text,
        "Missing reserved-X21 diagnostic",
    )
    compile_fixture(args, args.output / "reserved-control.s", flags)
    compile_fixture(
        args,
        args.output / "reserved-normal.s",
        [*flags, "-DPROTECTED", "-DORDINARY_RETURN"],
    )


def run_matrix(args: argparse.Namespace) -> list[dict[str, object]]:
    """Cover two optimization levels, public outcomes, residue and broken restores."""
    rows = []
    for opt, variant in itertools.product((0, 2), ("protected", "control")):
        assembly = args.output / f"{variant}-O{opt}.s"
        flags = [f"-O{opt}"] + (["-DPROTECTED"] if variant == "protected" else [])
        compile_fixture(args, assembly, flags)
        layout = frame_layout(assembly.read_text())
        binary = link_fixture(args, assembly)
        for mode, value in itertools.product(
            ("normal", "caught", "typed", "forced"), (7, 8)
        ):
            rows.append(
                runtime_case(
                    args, binary, layout, variant=variant, mode=mode, value=value
                )
            )
        if variant == "protected":
            text, count = omit_x21_restore(assembly.read_text())
            mutation = args.output / f"missing-x21-O{opt}.s"
            mutation.write_text(text)
            (args.output / f"missing-x21-O{opt}.json").write_text(
                json.dumps({"removed_restores": count}) + "\n"
            )
            broken = link_fixture(args, mutation)
            for value in (7, 8):
                rows.append(
                    runtime_case(
                        args,
                        broken,
                        layout,
                        variant=variant,
                        mode="forced",
                        value=value,
                        mutated=True,
                    )
                )
    return rows


def main() -> int:
    """Run against explicit tools and retain evidence without asserting milestone acceptance."""
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("clang", "cxx", "qemu", "sysroot", "output"):
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
    args.inputs = args.output / "inputs" / "zeroization-aarch64-cleanup"
    tools = tool_metadata(args)
    build_observer(args)
    rows = run_matrix(args)
    check_reserved(args)
    require(
        len(rows) == 36, "Expected 32 runtime cases and four detected restore mutations"
    )
    artifacts = {
        str(path.relative_to(args.output)): hashlib.sha256(
            path.read_bytes()
        ).hexdigest()
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
        "reserved_x21": "rejected; unprotected and protected ordinary controls compiled",
    }
    (args.output / "results.json").write_text(json.dumps(report, indent=2) + "\n")
    print(
        "PASS: 32 AArch64 runtime cases, four detected restore mutations, reserved-X21 checks"
    )
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError, subprocess.TimeoutExpired) as error:
        sys.exit(str(error))
