#!/usr/bin/env python3
# Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
# See https://llvm.org/LICENSE.txt for license information.
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Run the six frozen register-zeroing compatibility fixtures."""

import argparse
import hashlib
import json
import os
import subprocess
import sys
from pathlib import Path


def read_baseline(root: Path) -> dict[str, str]:
    """Read the six fixture hashes from the reviewed baseline manifest."""
    path = root / ".ci/zeroization-compatibility.json"
    files = json.loads(path.read_text())["files"]
    if not isinstance(files, dict) or len(files) != 6:
        raise ValueError(f"{path}: expected exactly six fixture hashes")
    return files


def verify_fixtures(root: Path, files: dict[str, str]) -> None:
    """Reject changed fixtures before running their frozen expectations."""
    for name, expected in files.items():
        actual = hashlib.sha256((root / name).read_bytes()).hexdigest()
        if actual != expected:
            raise ValueError(
                f"Baseline fixture changed: {name}. Review and document the behavior "
                "change before updating .ci/zeroization-compatibility.json."
            )


def expected_test_names(files: dict[str, str]) -> set[str]:
    """Map source fixture paths to their exact lit result names."""
    suites = {"llvm": "LLVM", "clang": "Clang"}
    names = set()
    for path in files:
        project, directory, relative = path.split("/", 2)
        if directory != "test" or ".." in Path(relative).parts:
            raise ValueError(f"Invalid compatibility fixture path: {path}")
        names.add(f"{suites[project]} :: {relative}")
    return names


def verify_results(report: Path, expected: set[str]) -> None:
    """Require one actual PASS result for every frozen fixture, with no extras."""
    results = json.loads(report.read_text())["tests"]
    actual = [result["name"] for result in results]
    if len(actual) != len(expected) or set(actual) != expected:
        raise ValueError(f"{report}: expected exactly the six named compatibility results")
    failed = [
        f"{result['name']}: {result['code']}" for result in results if result["code"] != "PASS"
    ]
    if failed:
        raise ValueError("Compatibility requires PASS for every fixture: " + "; ".join(failed))


def verify_build_source(root: Path, build: Path) -> None:
    """Require this checkout and a build that actually checks test expectations."""
    prefix = "CMAKE_HOME_DIRECTORY:INTERNAL="
    entries = (build / "CMakeCache.txt").read_text().splitlines()
    sources = [line.removeprefix(prefix) for line in entries if line.startswith(prefix)]
    if len(sources) != 1 or Path(sources[0]).resolve() != (root / "llvm").resolve():
        raise ValueError(
            f"{build}: configure this build from {root / 'llvm'} before running the gate"
        )
    profcheck = [
        line.split("=", 1)[1] for line in entries if line.startswith("LLVM_ENABLE_PROFCHECK:")
    ]
    if any(value.upper() not in ("OFF", "FALSE", "0", "NO", "N", "") for value in profcheck):
        raise ValueError(f"{build}: disable LLVM_ENABLE_PROFCHECK; it bypasses FileCheck")


def run_gate(root: Path, build: Path, report: Path) -> None:
    """Verify frozen inputs and run the configured compiler's compatibility suite."""
    files = read_baseline(root)
    expected = expected_test_names(files)
    verify_fixtures(root, files)
    verify_build_source(root, build)
    report.parent.mkdir(parents=True, exist_ok=True)
    report.unlink(missing_ok=True)
    # LIT_OPTS can enable --no-execute; filters and shards can omit fixtures.
    environment = {
        key: value
        for key, value in os.environ.items()
        if not key.startswith("LIT_") and key != "FILECHECK_OPTS"
    }
    command = [str(build / "bin/llvm-lit"), "-v", "--output", str(report)]
    command.extend(str(root / name) for name in files)
    result = subprocess.run(command, env=environment, check=False)
    if result.returncode:
        raise ValueError(f"Compatibility tests failed; inspect lit output and {report}")
    verify_results(report, expected)
    verify_fixtures(root, files)
    print("All six frozen register-zeroing compatibility fixtures passed.")


def main() -> int:
    """Run the gate using an existing LLVM/Clang build and retain its results."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build-dir", type=Path, default=Path("build"))
    parser.add_argument(
        "--report", type=Path, default=Path("artifacts/zeroization-compatibility.json")
    )
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    try:
        run_gate(root, args.build_dir.resolve(), args.report.resolve())
    except (OSError, ValueError, KeyError, TypeError) as error:
        print(f"Zeroization compatibility gate failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
