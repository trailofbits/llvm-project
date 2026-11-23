"""Behavior checks for ARM cleanup observation bounds and failure handling."""

import hashlib
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import check_zeroization_arm32_cleanup as runner

ASSEMBLY = """inner:
  .save {r4, lr}
  push {r4, lr}
  .pad #24
  sub sp, sp, #24
  bl action
  str r3, [r0, #4]
  bx r12
  .size inner, .-inner
"""
MIR = "name: inner\nframeInfo:\n  stackSize: 32\n"


def frame(data: bytes) -> str:
    return f"FRAME bytes={len(data)} hex={data.hex()}\n"


def private_result(omitted=None) -> str:
    text = frame(bytes(32))
    for index in (0, 1):
        data = bytearray(96)
        if index == omitted:
            data[36 if index == 0 else 92] = 1
        text += f"PRIVATE index={index} bytes=96 hex={data.hex()} returns=1 OR={int(any(data)):x}\n"
    return text + ("PASS mode=private\n" if omitted is None else "FAIL reason=private-residue\n")


def personalities() -> str:
    registers = "r4, r5, r6, r7, r8, r9, r10, r11, lr"
    text = ""
    for name in ("personality", "helper_personality"):
        symbol = f".Larm_zeroize_{name}_0"
        text += f"{symbol}:\n  .save {{{registers}}}\n  push {{{registers}}}\n"
        text += "  .pad #60\n  sub sp, sp, #60\n  bl runtime\n  ldm r12, {r4, lr}\n"
        text += "  str r1, [sp]\n"
        text += "".join(f"  str r1, [sp, #{offset}]\n" for offset in range(4, 96, 4))
        text += f"  add sp, sp, #96\n  bx lr\n  .fnend\n  .size {symbol}, .-{symbol}\n"
    return text


class ArmCleanupTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)

    def test_matching_arm_thumb_and_minimum_bounds(self):
        self.assertEqual(runner.frame_layout(ASSEMBLY, MIR), 32)
        thumb = ASSEMBLY.replace("push ", "push.w ").replace("sp, sp, #24", "sp, #24")
        self.assertEqual(runner.frame_layout(thumb, MIR), 32)
        minimum = ASSEMBLY.replace("  .pad #24\n  sub sp, sp, #24\n", "")
        self.assertEqual(runner.frame_layout(minimum, MIR.replace("32", "8")), 8)
        maximum = ASSEMBLY.replace("24", "216")
        self.assertEqual(runner.frame_layout(maximum, MIR.replace("32", "224")), 224)

    def test_ambiguous_or_inconsistent_layouts_are_rejected(self):
        cases = [
            ASSEMBLY.replace("bl action", "sub sp, sp, #8\n  bl action"),
            ASSEMBLY.replace("bl action", ".pad #8\n  sub sp, sp, #8\n  bl action"),
            ASSEMBLY.replace(".pad #24", ".pad #32"),
            ASSEMBLY.replace("push {r4, lr}", "push {r4, lr}\n  push {r5, r6}"),
            ASSEMBLY.replace("sub sp, sp, #24", "vpush {d8}"),
            ASSEMBLY.replace("sub sp, sp, #24", "str r0, [sp, #-24]!"),
            ASSEMBLY.replace("{r4, lr}", "{r4-r6, lr}"),
            ASSEMBLY.replace("{r4, lr}", "{lr, r4}"),
            ASSEMBLY.replace("bl action", "nop"),
            ASSEMBLY + ASSEMBLY,
        ]
        for text in cases:
            with self.subTest(text=text), self.assertRaises(ValueError):
                runner.frame_layout(text, MIR)
        for mir in (MIR + MIR, MIR.replace("32", "232"), MIR.replace("32", "24"), ""):
            with self.subTest(mir=mir), self.assertRaises(ValueError):
                runner.frame_layout(ASSEMBLY, mir)

    def test_original_mutation_requires_one_actual_cleanup_store(self):
        changed = runner.omit_original_wipe(ASSEMBLY)
        self.assertNotIn("str r3", changed)
        self.assertIn("bx r12", changed)
        for text in (
            ASSEMBLY.replace("str r3", "str r2"),
            ASSEMBLY.replace("bx r12", "str r3, [r0, #4]\n  bx r12"),
        ):
            with self.subTest(text=text), self.assertRaisesRegex(ValueError, "exactly one"):
                runner.omit_original_wipe(text)

    def test_private_mutations_keep_the_other_personality_intact(self):
        source = personalities()
        for omitted, offset in ((0, 36), (1, 92)):
            result = runner.instrument_private(source, omitted)
            self.assertEqual(result.count("Deliberately omit"), 1)
            self.assertEqual(result.count(f"str r1, [sp, #{offset}]"), 1)
            self.assertEqual(result.count("str sp,[r12]"), 2)

    def test_private_observer_rejects_partial_or_extended_allocations(self):
        source = personalities()
        cases = [
            source.replace("  str r1, [sp, #92]\n", ""),
            source.replace("add sp, sp, #96", "add sp, sp, #112"),
            source.replace("#60", "#76"),
            source.replace("  bx lr", "  str r1, [sp, #-4]\n  bx lr"),
            source.replace("  ldm r12", "  nop\n  ldm r11"),
            "",
        ]
        for text in cases:
            with self.subTest(text=text), self.assertRaises(ValueError):
                runner.instrument_private(text, None)

    def test_behavior_and_actual_frame_observations(self):
        runner.check_observation("PASS mode=normal\n", mode="normal", variant="protected", size=32)
        for variant, data in (("protected", bytes(32)), ("control", bytes([1]) * 32)):
            runner.check_observation(
                frame(data) + "PASS mode=forced\n", mode="forced", variant=variant, size=32
            )

    def test_missing_partial_duplicate_or_wrong_residue_fails(self):
        good = frame(bytes(32)) + "PASS mode=forced\n"
        cases = [
            "",
            "PASS mode=forced\n",
            good + good,
            good.replace("bytes=32", "bytes=16"),
            frame(bytes(16)) + "PASS mode=forced\n",
            frame(bytes([1]) * 32) + "PASS mode=forced\n",
            good + "FAIL reason=caller-context\n",
        ]
        for text in cases:
            with self.subTest(text=text), self.assertRaises(ValueError):
                runner.check_observation(text, mode="forced", variant="protected", size=32)
        with self.assertRaisesRegex(ValueError, "residue"):
            runner.check_observation(good, mode="forced", variant="control", size=32)

    def test_both_private_boundaries_and_precise_failures_are_required(self):
        for omitted in (None, 0, 1):
            runner.check_private(private_result(omitted), omitted)
        good = private_result()
        cases = [
            good.replace("index=1", "index=0"),
            good.replace("returns=1", "returns=0"),
            good.replace("00" * 96, "00" * 92),
            private_result(0),
            good.replace("FRAME bytes=32", "FRAME bytes=96"),
        ]
        for text in cases:
            with self.subTest(text=text), self.assertRaises(ValueError):
                runner.check_private(text, None)
        with self.assertRaises(ValueError):
            runner.check_private(private_result(0).replace("private-residue", "other"), 0)
        with self.assertRaises(ValueError):
            runner.check_private(private_result(0), 1)

    def test_source_bytes_and_runner_are_retained(self):
        hashes = runner.copy_inputs(self.root)
        source = Path(runner.__file__).parent
        for relative, digest in hashes.items():
            original = source / Path(relative).relative_to("inputs")
            copied = self.root / relative
            self.assertEqual(original.read_bytes(), copied.read_bytes())
            self.assertEqual(hashlib.sha256(copied.read_bytes()).hexdigest(), digest)
        self.assertIn("inputs/check_zeroization_arm32_cleanup.py", hashes)

    def test_failed_command_keeps_diagnostics_and_exact_status(self):
        log = self.root / "command.log"
        with self.assertRaisesRegex(ValueError, "Expected exit 0, got 3"):
            runner.execute([sys.executable, "-c", "print('diagnostic'); exit(3)"], log)
        self.assertIn("diagnostic\nexit=3", log.read_text())
        with self.assertRaisesRegex(ValueError, "Expected exit 79, got 0"):
            runner.execute([sys.executable, "-c", "print('wrong success')"], log, expected=79)

    def test_timeout_keeps_partial_output(self):
        log = self.root / "timeout.log"
        error = subprocess.TimeoutExpired(["compiler"], 30, output=b"partial output\n")
        with (
            mock.patch.object(subprocess, "run", side_effect=error),
            self.assertRaisesRegex(ValueError, "timed out"),
        ):
            runner.execute(["compiler"], log)
        self.assertIn("partial output\n\nTIMEOUT", log.read_text())

    def test_existing_evidence_directory_is_not_overwritten(self):
        sentinel = self.root / "results.json"
        sentinel.write_text("previous evidence\n")
        argv = [
            "runner",
            "--source-revision",
            "0" * 40,
            "--sysroot",
            str(self.root),
            "--output",
            str(self.root),
        ]
        for name in ("clang", "llc", "cxx", "qemu", "nm"):
            argv.extend([f"--{name}", sys.executable])
        with mock.patch.object(sys, "argv", argv), self.assertRaises(FileExistsError):
            runner.main()
        self.assertEqual(sentinel.read_text(), "previous evidence\n")


if __name__ == "__main__":
    unittest.main()
