"""Behavior checks for the AArch64 cleanup observer's CI runner."""

import argparse
import hashlib
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import check_zeroization_aarch64_cleanup as runner

ASSEMBLY = """inner:
  str d8, [sp, #-64]!
  .cfi_def_cfa_offset 64
  .cfi_offset w30, -40
  bl action
  ldr x21, [x9] // Reload
  ldr x19, [x9]
  ldr x21, [x8] // Reload
  .size inner, .-inner
"""
PROTECTED = (
    "FRAME bytes=16 hex="
    + "00" * 16
    + "\nCONTEXT restored=1 helper-disjoint=1\nPASS mode=forced\n"
)
CONTROL = "FRAME bytes=16 hex=" + "01" * 16 + "\nPASS mode=forced\n"


class CleanupTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)

    def test_layout_matches_machine_allocation_and_lr_rule(self):
        self.assertEqual(runner.frame_layout(ASSEMBLY), (64, 24))
        self.assertEqual(
            runner.frame_layout(
                ASSEMBLY.replace("str d8, [sp, #-64]!", "sub sp, sp, #64")
            ),
            (64, 24),
        )
        self.assertEqual(
            runner.frame_layout(
                ASSEMBLY.replace("  bl action", "  .cfi_def_cfa w29, 48\n  bl action")
            ),
            (64, 24),
        )

    def test_split_prologue_cannot_underreport_the_original_frame(self):
        split = """inner:
  sub sp, sp, #64
  .cfi_def_cfa_offset 64
  sub sp, sp, #16
  .cfi_def_cfa_offset 80
  .cfi_offset w30, -40
  bl action
  .size inner, .-inner
"""
        cases = [
            split,
            split.replace("  .cfi_def_cfa_offset 80\n", ""),
            split.replace("  sub sp, sp, #16\n", ""),
            split.replace("sub sp, sp, #16", "str x0, [sp, #-16]!").replace(
                "  .cfi_def_cfa_offset 80\n", ""
            ),
        ]
        for text in cases:
            with (
                self.subTest(text=text),
                self.assertRaisesRegex(ValueError, "Expected one"),
            ):
                runner.frame_layout(text)

    def test_layout_rejects_missing_inconsistent_or_invalid_bounds(self):
        changes = [
            ("inner:", "other:"),
            (".size inner", ".size other"),
            (".cfi_def_cfa_offset 64", ""),
            ("#-64", "#-32"),
            (".cfi_offset w30, -40", ""),
            ("-40", "-72"),
            ("-40", "-3"),
            ("str d8, [sp, #-64]!", "nop"),
            ("bl action", "nop"),
        ]
        for old, new in changes:
            with self.subTest(old=old, new=new), self.assertRaises(ValueError):
                runner.frame_layout(ASSEMBLY.replace(old, new))

    def test_mutation_removes_real_restores_only(self):
        text, count = runner.omit_x21_restore(ASSEMBLY)
        self.assertEqual(count, 2)
        self.assertNotIn("ldr x21", text)
        self.assertIn("ldr x19", text)
        self.assertEqual(runner.frame_layout(text), (64, 24))

    def test_mutation_cannot_silently_skip_or_remove_sp_updates(self):
        for text in ("nop\n", "ldr x21, [sp], #16\n", "ldr x21, [sp, #16]!\n"):
            with (
                self.subTest(text=text),
                self.assertRaisesRegex(ValueError, "did not find"),
            ):
                runner.omit_x21_restore(text)

    def test_observed_protected_and_control_frames(self):
        runner.check_observation(PROTECTED, variant="protected", mode="forced", size=16)
        runner.check_observation(CONTROL, variant="control", mode="forced", size=16)
        for mode in ("normal", "caught", "typed"):
            runner.check_observation(
                f"PASS mode={mode}\n", variant="protected", mode=mode, size=16
            )

    def test_false_or_truncated_observations_are_rejected(self):
        cases = [
            "",
            PROTECTED + "PASS mode=forced\n",
            PROTECTED + "FAIL reason=bad\n",
            PROTECTED.replace("bytes=16", "bytes=32"),
            PROTECTED.replace("00" * 16, "00" * 8),
            PROTECTED.replace("00" * 16, "01" * 16),
            PROTECTED.replace("CONTEXT restored=1 helper-disjoint=1\n", ""),
        ]
        for text in cases:
            with self.subTest(text=text), self.assertRaises(ValueError):
                runner.check_observation(
                    text, variant="protected", mode="forced", size=16
                )
        with self.assertRaisesRegex(ValueError, "residue"):
            runner.check_observation(
                PROTECTED, variant="control", mode="forced", size=16
            )

    def test_copied_inputs_are_identical_and_runner_is_retained(self):
        hashes = runner.copy_inputs(self.root)
        source = Path(runner.__file__).parent
        names = ["check_zeroization_aarch64_cleanup.py"] + [
            f"zeroization-aarch64-cleanup/{name}"
            for name in ("inner.cpp", "observer.cpp", "markers.S")
        ]
        for name in names:
            data = (self.root / "inputs" / name).read_bytes()
            self.assertEqual(data, (source / name).read_bytes())
            self.assertEqual(hashes["inputs/" + name], hashlib.sha256(data).hexdigest())

    def test_failed_command_preserves_output_and_status(self):
        log = self.root / "command.log"
        with self.assertRaisesRegex(ValueError, "Expected exit 0, got 3"):
            runner.execute([sys.executable, "-c", "print('diagnostic'); exit(3)"], log)
        self.assertIn("diagnostic\nexit=3", log.read_text())

    def test_timeout_preserves_partial_output(self):
        log = self.root / "timeout.log"
        error = subprocess.TimeoutExpired(
            ["compiler"], 30, output=b"partial compiler output\n"
        )
        with (
            mock.patch.object(subprocess, "run", side_effect=error),
            self.assertRaisesRegex(ValueError, "timed out"),
        ):
            runner.execute(["compiler"], log)
        self.assertIn("partial compiler output\n\nTIMEOUT", log.read_text())

    def test_runtime_status_and_required_observation_are_both_checked(self):
        binary = self.root / "observer.py"
        args = argparse.Namespace(output=self.root, qemu=Path(sys.executable))
        binary.write_text(f"print({PROTECTED!r}, end='')\n")
        row = runner.runtime_case(
            args, binary, (16, 8), variant="protected", mode="forced", value=7
        )
        self.assertTrue(row["passed"])
        binary.write_text("print('nothing observed')\n")
        with self.assertRaisesRegex(ValueError, "success marker"):
            runner.runtime_case(
                args, binary, (16, 8), variant="protected", mode="forced", value=8
            )

    def test_mutation_requires_the_specific_observer_failure(self):
        binary = self.root / "observer.py"
        args = argparse.Namespace(output=self.root, qemu=Path(sys.executable))
        binary.write_text("print('FAIL reason=caller-x21'); exit(76)\n")
        runner.runtime_case(
            args,
            binary,
            (16, 8),
            variant="protected",
            mode="forced",
            value=7,
            mutated=True,
        )
        for output, status in (
            ("FAIL reason=other", 76),
            ("FAIL reason=caller-x21", 0),
        ):
            binary.write_text(f"print({output!r}); exit({status})\n")
            with (
                self.subTest(output=output, status=status),
                self.assertRaises(ValueError),
            ):
                runner.runtime_case(
                    args,
                    binary,
                    (16, 8),
                    variant="protected",
                    mode="forced",
                    value=8,
                    mutated=True,
                )


if __name__ == "__main__":
    unittest.main()
