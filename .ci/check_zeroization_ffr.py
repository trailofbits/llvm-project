#!/usr/bin/env python3
# Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Execute SVE FFR clearing and its negative controls with a supplied compiler."""

import argparse
import hashlib
import itertools
import json
import re
import shlex
import struct
import subprocess
import sys
from contextlib import nullcontext
from dataclasses import asdict, dataclass
from pathlib import Path


@dataclass(frozen=True, kw_only=True)
class Case:
    mode: str
    variant: str
    opt: int
    abi: str
    vl: int
    selector: int

    def name(self) -> str:
        """Return the unique artifact prefix for this execution."""
        return f"{self.mode}-{self.variant}-O{self.opt}-{self.abi}-{self.vl}-{self.selector}"


def require(condition: bool, message: str) -> None:
    """Reject a failed observation even when Python assertions are disabled."""
    if not condition:
        raise ValueError(message)


def without_ffr(assembly: str) -> tuple[str, int]:
    """Delete one actual FFR clear per return, rejecting an ineffective control."""
    pattern = r"^\s*wrffr\s+p\d+\.b\s*(?://[^\n]*)?$"
    result, count = re.subn(pattern, "", assembly, flags=re.MULTILINE)
    returns = len(re.findall(r"^\s*ret\s*(?://[^\n]*)?$", assembly, re.MULTILINE))
    require(
        count == returns and count >= 2, "Expected an FFR clear at every fixture return"
    )
    return result, count


def unprotected(source: str) -> str:
    """Remove the single clearing attribute group from a fixture."""
    result, count = re.subn(
        r"^attributes #0 = .+$",
        "attributes #0 = { nounwind }",
        source,
        flags=re.MULTILINE,
    )
    require(count == 1, "Expected exactly one fixture attribute group")
    return result


def check_interfaces(
    words: tuple[int, ...], vectors: list[bytes], predicates: list[bytes], case: Case
) -> None:
    """Check the scalar/vector/predicate result and required preserved values."""
    if case.abi == "base":
        require(words[0] == 67 + case.selector, "Scalar result changed")
        require(all(v[:8] == bytes([11]) * 8 for v in vectors[8:16]), "D8-D15 changed")
        return
    require(all(v == bytes([11]) * case.vl for v in vectors[8:24]), "Z8-Z23 changed")
    require(
        all(p == bytes([255]) * (case.vl // 8) for p in predicates[4:]),
        "P4-P15 changed",
    )
    if case.mode == "used":
        require(
            predicates[0] == bytes([255]) * (case.vl // 8), "Predicate result changed"
        )
    else:
        value = 5 if case.selector == 0 else 3
        require(vectors[0] == bytes([value]) * case.vl, "Vector result changed")


def check_all_clears(
    words: tuple[int, ...], vectors: list[bytes], predicates: list[bytes], case: Case
) -> None:
    """Check the other covered registers in the all-mode protected fixture."""
    require(words[19] == 0, "NZCV was not cleared")
    first = 1 if case.abi == "base" else 0
    require(all(value == 0 for value in words[first:19]), "GPR residue remains")
    preserved = range(8, 16) if case.abi == "base" else range(8, 24)
    for index, value in enumerate(vectors):
        if index not in preserved and not (case.abi == "vector" and index == 0):
            require(value == bytes(case.vl), f"Z{index} residue remains")
    if case.abi == "base":
        require(
            all(v[8:] == bytes(case.vl - 8) for v in vectors[8:16]),
            "Upper-lane residue",
        )
    cleared = predicates if case.abi == "base" else predicates[:4]
    require(all(p == bytes(case.vl // 8) for p in cleared), "Predicate residue remains")


def check_snapshot(data: bytes, case: Case) -> str:
    """Validate a complete immediate-return snapshot and return its FFR hex."""
    vl = case.vl
    require(
        len(data) == 200 + 32 * vl + 17 * (vl // 8), "Truncated or extra snapshot data"
    )
    words = struct.unpack_from("<25Q", data)
    require(words[22] == vl, "QEMU did not execute at the requested vector length")
    require(words[24] == case.selector, "Wrong invocation selector")
    require(words[20] == words[21], "Stack pointer was not restored")
    vectors = [data[200 + i * vl : 200 + (i + 1) * vl] for i in range(32)]
    start = 200 + 32 * vl
    predicates = [
        data[start + i * (vl // 8) : start + (i + 1) * (vl // 8)] for i in range(16)
    ]
    ffr = data[start + 16 * (vl // 8) :]
    expected = 0 if case.variant == "protected" else 255
    require(ffr == bytes([expected]) * (vl // 8), f"Unexpected FFR state: {ffr.hex()}")
    check_interfaces(words, vectors, predicates, case)
    if case.mode == "all" and case.variant != "unprotected":
        check_all_clears(words, vectors, predicates, case)
    return ffr.hex()


def run(
    command: list[str], log: Path, *, stdout: Path | None = None, timeout: int = 60
) -> None:
    """Run one tool with a bounded wait and preserve its command and diagnostics."""
    with log.open("ab") as stream:
        stream.write((shlex.join(command) + "\n").encode())
        stream.flush()
        with stdout.open("wb") if stdout else nullcontext(stream) as output:
            result = subprocess.run(
                command, stdout=output, stderr=stream, timeout=timeout, check=False
            )
    if result.returncode:
        raise RuntimeError(f"{command[0]} exited {result.returncode}; see {log}")


def copy_inputs(output: Path) -> dict[str, str]:
    """Preserve the runner and fixtures before execution, with their source layout."""
    source_dir = Path(__file__).resolve().parent
    names = (
        "check_zeroization_ffr.py",
        "zeroization-ffr/all.ll",
        "zeroization-ffr/used.ll",
        "zeroization-ffr/observer.S",
    )
    hashes = {}
    for name in names:
        data = (source_dir / name).read_bytes()
        destination = output / "inputs" / name
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(data)
        hashes[name] = hashlib.sha256(data).hexdigest()
    return hashes


def build_variants(args: argparse.Namespace, mode: str, opt: int) -> dict[str, Path]:
    """Compile protected/control fixtures and assemble a checked missing-clear mutation."""
    source_dir = args.output / "inputs" / "zeroization-ffr"
    prefix = args.output / f"{mode}-O{opt}"
    control = prefix.with_suffix(".ll")
    control.write_text(unprotected((source_dir / f"{mode}.ll").read_text()))
    objects = {}
    for variant in ("protected", "unprotected", "missing-ffr"):
        assembly = args.output / f"{mode}-{variant}-O{opt}.s"
        if variant == "missing-ffr":
            protected = args.output / f"{mode}-protected-O{opt}.s"
            text, removed = without_ffr(protected.read_text())
            assembly.write_text(text)
            print(f"{mode} O{opt}: removed {removed} WRFFR instructions", flush=True)
        else:
            source = control if variant == "unprotected" else source_dir / f"{mode}.ll"
            run(
                [
                    str(args.llc),
                    "-mtriple=aarch64-linux-gnu",
                    "-mattr=+sve",
                    "-verify-machineinstrs",
                    f"-O{opt}",
                    str(source),
                    "-o",
                    str(assembly),
                ],
                args.output / "commands.log",
            )
        obj = assembly.with_suffix(".o")
        run(
            [
                str(args.clang),
                "--target=aarch64-linux-gnu",
                "-march=armv8-a+sve",
                "-c",
                str(assembly),
                "-o",
                str(obj),
            ],
            args.output / "commands.log",
        )
        objects[variant] = obj
    return objects


def observe(args: argparse.Namespace, obj: Path, case: Case) -> dict[str, object]:
    """Link and run one case, keeping raw state even when validation fails."""
    executable = obj.with_name(f"{obj.stem}-{case.abi}.elf")
    log = args.output / "commands.log"
    if not executable.exists():
        run(
            [
                str(args.linker),
                "-m",
                "aarch64elf",
                "-static",
                str(args.output / f"{case.abi}-observer.o"),
                str(obj),
                "-o",
                str(executable),
            ],
            log,
        )
    snapshot = args.output / f"{case.name()}.bin"
    command = [
        str(args.qemu),
        "-cpu",
        f"max,sve-max-vq=16,sve-default-vector-length={case.vl}",
        str(executable),
    ]
    if case.selector:
        command.append("late")
    run(command, log, stdout=snapshot, timeout=10)
    try:
        ffr = check_snapshot(snapshot.read_bytes(), case)
    except ValueError as error:
        raise ValueError(f"{case.name()}: {error}") from error
    return {**asdict(case), "snapshot": snapshot.name, "ffr": ffr, "passed": True}


def main() -> int:
    """Run the complete current-compiler matrix and write an explicit success report."""
    parser = argparse.ArgumentParser(description=__doc__)
    for tool in ("llc", "clang", "linker", "qemu"):
        parser.add_argument(f"--{tool}", type=Path, required=True)
    parser.add_argument(
        "--output", type=Path, required=True, help="New directory for evidence"
    )
    args = parser.parse_args()
    args.output = args.output.resolve()
    args.output.mkdir(parents=True, exist_ok=False)
    inputs = copy_inputs(args.output)
    source_dir = args.output / "inputs" / "zeroization-ffr"
    tools = {}
    for name in ("llc", "clang", "linker", "qemu"):
        path = getattr(args, name).absolute()
        require(path.is_file(), f"Missing {name} executable: {path}")
        setattr(args, name, path)
        run(
            [str(path), "--version"],
            args.output / "commands.log",
            stdout=args.output / f"{name}.txt",
        )
        tools[name] = {
            "path": str(path),
            "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
        }
    for abi in ("base", "vector"):
        flags = ["-DBASE"] if abi == "base" else []
        run(
            [
                str(args.clang),
                "--target=aarch64-linux-gnu",
                "-march=armv8-a+sve",
                *flags,
                "-c",
                str(source_dir / "observer.S"),
                "-o",
                str(args.output / f"{abi}-observer.o"),
            ],
            args.output / "commands.log",
        )
    rows = []
    for mode, opt in itertools.product(("all", "used"), (0, 2)):
        objects = build_variants(args, mode, opt)
        for variant, abi, vl, selector in itertools.product(
            objects, ("base", "vector"), (16, 64, 256), (0, 1)
        ):
            case = Case(
                mode=mode, variant=variant, opt=opt, abi=abi, vl=vl, selector=selector
            )
            rows.append(observe(args, objects[variant], case))
    require(
        len(rows) == 144, "Expected 48 protected observations and 96 negative controls"
    )
    report = {"success": True, "tools": tools, "inputs": inputs, "observations": rows}
    (args.output / "results.json").write_text(json.dumps(report, indent=2) + "\n")
    print("PASS: 48 protected FFR observations and 96 negative controls")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError, RuntimeError, subprocess.TimeoutExpired) as error:
        sys.exit(str(error))
