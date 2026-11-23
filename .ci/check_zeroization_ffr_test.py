#!/usr/bin/env python3
# Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Test snapshot rejection and negative-control construction without LLVM tools."""

import hashlib
import struct
import subprocess
import sys
import tempfile
import unittest
from dataclasses import replace
from pathlib import Path

from check_zeroization_ffr import (
    Case,
    check_snapshot,
    copy_inputs,
    run,
    unprotected,
    without_ffr,
)


class FFRTests(unittest.TestCase):
    def setUp(self) -> None:
        self.case = Case(
            mode="used", variant="protected", opt=2, abi="vector", vl=64, selector=1
        )
        words = [0] * 25
        words[20] = words[21] = 4096
        words[22], words[24] = 64, 1
        vectors = bytearray(32 * 64)
        vectors[8 * 64 : 24 * 64] = bytes([11]) * (16 * 64)
        predicates = bytearray(16 * 8)
        predicates[:8] = bytes([255]) * 8
        predicates[4 * 8 :] = bytes([255]) * (12 * 8)
        self.data = bytearray(
            struct.pack("<25Q", *words) + vectors + predicates + bytes(8)
        )

    def test_complete_predicate_result(self) -> None:
        self.assertEqual(check_snapshot(bytes(self.data), self.case), "00" * 8)

    def test_residue_in_high_ffr_bit(self) -> None:
        self.data[-1] = 128
        with self.assertRaisesRegex(ValueError, "FFR state"):
            check_snapshot(bytes(self.data), self.case)

    def test_control_must_retain_ffr(self) -> None:
        control = replace(self.case, variant="missing-ffr")
        with self.assertRaisesRegex(ValueError, "FFR state"):
            check_snapshot(bytes(self.data), control)
        self.data[-8:] = bytes([255]) * 8
        self.assertEqual(check_snapshot(bytes(self.data), control), "ff" * 8)

    def test_result_and_preserved_bits(self) -> None:
        for offset, message in (
            (200 + 32 * 64 + 7, "Predicate result"),
            (200 + 32 * 64 + 6 * 8 + 7, "P4-P15"),
            (200 + 20 * 64 + 63, "Z8-Z23"),
        ):
            data = self.data.copy()
            data[offset] = 0
            with (
                self.subTest(offset=offset),
                self.assertRaisesRegex(ValueError, message),
            ):
                check_snapshot(bytes(data), self.case)

    def test_shape_and_header(self) -> None:
        for data in (b"", bytes(self.data[:-1]), bytes(self.data) + b"\0"):
            with (
                self.subTest(length=len(data)),
                self.assertRaisesRegex(ValueError, "snapshot data"),
            ):
                check_snapshot(data, self.case)
        for field, value, message in (
            (22, 16, "vector length"),
            (24, 0, "selector"),
            (20, 4095, "Stack pointer"),
        ):
            data = self.data.copy()
            struct.pack_into("<Q", data, field * 8, value)
            with self.subTest(field=field), self.assertRaisesRegex(ValueError, message):
                check_snapshot(bytes(data), self.case)

    def test_all_mode_checks_other_clears(self) -> None:
        case = replace(self.case, mode="all", abi="base")
        words = [0] * 25
        words[0], words[22], words[24] = 68, 64, 1
        data = bytearray(struct.pack("<25Q", *words) + bytes(32 * 64 + 17 * 8))
        for reg in range(8, 16):
            data[200 + reg * 64 : 200 + reg * 64 + 8] = bytes([11]) * 8
        check_snapshot(bytes(data), case)
        for offset, message in (
            (8, "GPR residue"),
            (152, "NZCV"),
            (200 + 8 * 64 + 63, "Upper-lane"),
            (200 + 32 * 64, "Predicate residue"),
        ):
            changed = data.copy()
            changed[offset] = 1
            with (
                self.subTest(offset=offset),
                self.assertRaisesRegex(ValueError, message),
            ):
                check_snapshot(bytes(changed), case)

    def test_mutation_removes_every_return_clear(self) -> None:
        assembly = (
            "first:\n\twrffr\tp0.b\n\tret\nsecond:\n  wrffr p1.b // clear\n  ret\n"
        )
        changed, count = without_ffr(assembly)
        self.assertEqual(count, 2)
        self.assertNotIn("wrffr", changed)
        self.assertEqual(changed.count("ret"), 2)

    def test_ineffective_or_partial_mutation_rejected(self) -> None:
        for assembly in (
            "ret\nret\n",
            "wrffr p0.b\nret\nret\n",
            '// wrffr p0.b\n.ascii "wrffr p0.b"\nret\nret\n',
        ):
            with (
                self.subTest(assembly=assembly),
                self.assertRaisesRegex(ValueError, "every fixture"),
            ):
                without_ffr(assembly)

    def test_unprotected_has_no_clearing_request(self) -> None:
        source = (
            "define void @f() #0 { ret void }\n"
            'attributes #0 = { "zero-call-used-regs"="all" }\n'
        )
        result = unprotected(source)
        self.assertNotIn("zero-call-used-regs", result)
        self.assertIn("define void @f() #0", result)
        for invalid in ("ret void", source + source):
            with self.assertRaisesRegex(ValueError, "exactly one"):
                unprotected(invalid)

    def test_copied_inputs_match_original_bytes_and_hashes(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            hashes = copy_inputs(output)
            self.assertEqual(
                set(hashes),
                {
                    "check_zeroization_ffr.py",
                    "zeroization-ffr/all.ll",
                    "zeroization-ffr/used.ll",
                    "zeroization-ffr/observer.S",
                },
            )
            replay = output / "replay"
            command = [sys.executable, str(output / "inputs/check_zeroization_ffr.py")]
            for tool in ("llc", "clang", "linker", "qemu"):
                command.extend([f"--{tool}", str(output / "missing-tool")])
            command.extend(["--output", str(replay)])
            result = subprocess.run(
                command, capture_output=True, text=True, timeout=10, check=False
            )
            self.assertEqual(result.returncode, 1)
            self.assertIn("Missing llc executable", result.stderr)
            self.assertFalse((replay / "results.json").exists())
            source_dir = Path(__file__).resolve().parent
            for name, digest in hashes.items():
                copied = (output / "inputs" / name).read_bytes()
                self.assertEqual(copied, (source_dir / name).read_bytes())
                self.assertEqual(hashlib.sha256(copied).hexdigest(), digest)
                self.assertEqual((replay / "inputs" / name).read_bytes(), copied)

    def test_tool_failure_and_timeout(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            log = Path(directory) / "commands.log"
            with self.assertRaisesRegex(RuntimeError, "exited 7"):
                run([sys.executable, "-c", "import sys; sys.exit(7)"], log)
            self.assertIn("sys.exit(7)", log.read_text())
            with self.assertRaises(subprocess.TimeoutExpired):
                run(
                    [sys.executable, "-c", "import time; time.sleep(60)"],
                    log,
                    timeout=1,
                )
            with self.assertRaises(FileNotFoundError):
                run([str(Path(directory) / "missing-tool")], log)


if __name__ == "__main__":
    unittest.main()
