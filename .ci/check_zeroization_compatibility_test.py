# Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
# See https://llvm.org/LICENSE.txt for license information.
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Behavior tests for the frozen register-zeroing compatibility gate."""

import hashlib
import json
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from check_zeroization_compatibility import (
    expected_test_names,
    read_baseline,
    run_gate,
    verify_build_source,
    verify_fixtures,
    verify_results,
)


class CompatibilityGateTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.files = {f"llvm/test/CodeGen/test{index}.ll": "" for index in range(6)}
        self.expected = expected_test_names(self.files)
        self.report = self.root / "results.json"

    def write_results(self, entries):
        self.report.write_text(json.dumps({"tests": entries}))

    def passing_results(self):
        return [{"name": name, "code": "PASS"} for name in sorted(self.expected)]

    def create_fixtures(self):
        for name in self.files:
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("fixture\n")
            self.files[name] = hashlib.sha256(path.read_bytes()).hexdigest()
        manifest = self.root / ".ci/zeroization-compatibility.json"
        manifest.parent.mkdir()
        manifest.write_text(json.dumps({"files": self.files}))
        build = self.root / "build"
        build.mkdir()
        (build / "CMakeCache.txt").write_text(
            f"CMAKE_HOME_DIRECTORY:INTERNAL={self.root / 'llvm'}\n"
        )

    def test_all_six_pass(self):
        self.write_results(self.passing_results())
        verify_results(self.report, self.expected)

    def test_missing_extra_or_duplicate_results_fail(self):
        results = self.passing_results()
        different = results[:-1] + [{"name": "unrequested test", "code": "PASS"}]
        for entries in (
            [],
            results[:-1],
            results + [results[0]],
            results[:-1] + [results[0]],
            different,
        ):
            with self.subTest(entries=entries), self.assertRaisesRegex(ValueError, "exactly"):
                self.write_results(entries)
                verify_results(self.report, self.expected)

    def test_non_pass_results_fail(self):
        for code in ("FAIL", "UNSUPPORTED", "SKIPPED", "EXCLUDED", "XFAIL", "FLAKYPASS"):
            with self.subTest(code=code), self.assertRaisesRegex(ValueError, "requires PASS"):
                results = self.passing_results()
                results[0]["code"] = code
                self.write_results(results)
                verify_results(self.report, self.expected)

    def test_changed_or_missing_fixture_fails(self):
        self.create_fixtures()
        verify_fixtures(self.root, self.files)
        fixture = self.root / next(iter(self.files))
        fixture.write_text("changed expectation\n")
        with self.assertRaisesRegex(ValueError, "Baseline fixture changed"):
            verify_fixtures(self.root, self.files)
        fixture.unlink()
        with self.assertRaises(FileNotFoundError):
            verify_fixtures(self.root, self.files)

    def test_baseline_cannot_drop_a_fixture(self):
        manifest = self.root / ".ci/zeroization-compatibility.json"
        manifest.parent.mkdir()
        manifest.write_text(json.dumps({"files": dict(list(self.files.items())[:5])}))
        with self.assertRaisesRegex(ValueError, "exactly six"):
            read_baseline(self.root)

    def test_wrong_source_checkout_fails(self):
        self.create_fixtures()
        verify_build_source(self.root, self.root / "build")
        with self.assertRaisesRegex(ValueError, "configure this build"):
            verify_build_source(self.root / "other", self.root / "build")

    def test_profile_mode_cannot_bypass_filecheck(self):
        self.create_fixtures()
        cache = self.root / "build/CMakeCache.txt"
        original = cache.read_text()
        for option in ("BOOL=ON", "UNINITIALIZED=1"):
            cache.write_text(original + f"LLVM_ENABLE_PROFCHECK:{option}\n")
            with self.subTest(option=option), self.assertRaisesRegex(
                ValueError, "bypasses FileCheck"
            ):
                verify_build_source(self.root, self.root / "build")
        cache.write_text(original + "LLVM_ENABLE_PROFCHECK:BOOL=OFF\n")
        verify_build_source(self.root, self.root / "build")

    def test_execution_overrides_and_stale_results_are_removed(self):
        self.create_fixtures()
        self.write_results(self.passing_results())

        def execute(command, *, env, check):
            for key in ("LIT_OPTS", "LIT_FILTER", "LIT_NUM_SHARDS", "FILECHECK_OPTS"):
                self.assertNotIn(key, env)
            self.assertFalse(self.report.exists())
            raise FileNotFoundError("missing configured llvm-lit")

        overrides = {"LIT_OPTS": "--no-execute", "LIT_FILTER": "none", "LIT_NUM_SHARDS": "2"}
        with patch.dict("os.environ", overrides | {"FILECHECK_OPTS": "--allow-empty"}):
            with patch(
                "check_zeroization_compatibility.subprocess.run", side_effect=execute
            ) as run:
                with self.assertRaises(FileNotFoundError):
                    run_gate(self.root, self.root / "build", self.report)
                run.assert_called_once()

    def test_success_without_fresh_report_fails(self):
        self.create_fixtures()
        self.write_results(self.passing_results())
        success = subprocess.CompletedProcess([], 0)
        with patch("check_zeroization_compatibility.subprocess.run", return_value=success):
            with self.assertRaises(FileNotFoundError):
                run_gate(self.root, self.root / "build", self.report)

    def test_nonzero_exit_overrides_a_passing_report(self):
        self.create_fixtures()

        def execute(command, *, env, check):
            self.write_results(self.passing_results())
            return subprocess.CompletedProcess(command, 1)

        with patch("check_zeroization_compatibility.subprocess.run", side_effect=execute):
            with self.assertRaisesRegex(ValueError, "Compatibility tests failed"):
                run_gate(self.root, self.root / "build", self.report)

    def test_fixture_change_during_execution_fails(self):
        self.create_fixtures()

        def execute(command, *, env, check):
            (self.root / next(iter(self.files))).write_text("updated during execution\n")
            self.write_results(self.passing_results())
            return subprocess.CompletedProcess(command, 0)

        with patch("check_zeroization_compatibility.subprocess.run", side_effect=execute):
            with self.assertRaisesRegex(ValueError, "Baseline fixture changed"):
                run_gate(self.root, self.root / "build", self.report)


if __name__ == "__main__":
    unittest.main()
