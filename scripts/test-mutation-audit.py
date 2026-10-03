#!/usr/bin/env python3
"""Detection classification is a safety contract, not an exit-code score."""
import importlib.util
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
spec = importlib.util.spec_from_file_location("audit", Path(__file__).with_name("mutation-audit.py"))
audit = importlib.util.module_from_spec(spec)
spec.loader.exec_module(audit)


class ClassificationTest(unittest.TestCase):
    def classify(self, code, text, witness=None):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "worker.log"
            path.write_text(text)
            row = {"exit": code, "log": str(path)}
            result = audit.classify(row, witness)
            return result, row["failing_tests"]

    def test_assertion_detection_requires_a_named_test(self):
        result, names = self.classify(2, "  1) test cash stays protected (FinanceTest)\nAssertion with == failed\ncode: assert cash == 100\n")
        self.assertEqual(result, "detected")
        self.assertEqual(names, ["test cash stays protected (FinanceTest)"])
        self.assertEqual(self.classify(2, "Assertion with == failed")[0], "harness_failure")

    def test_flunk_messages_are_valid_witnesses(self):
        text = "  1) property controls reject (PayloadTest)\nunsafe name committed\n"
        self.assertEqual(self.classify(2, text, "unsafe name committed")[0], "detected")
        self.assertEqual(self.classify(2, text, "different invariant")[0], "harness_failure")

    def test_setup_compile_timeout_and_success_are_not_kills(self):
        prefix = "  1) test handoff (PersistenceTest)\n"
        for code, suffix, expected in [
            (2, "** (CompileError) missing function", "invalid_compile"),
            (2, "failed to start child GameServer", "setup_failure"),
            (2, "  0) PersistenceTest: failure on setup_all callback, all tests have been invalidated", "setup_failure"),
            (2, "test/foo.exs:12: PersistenceTest.__ex_unit_setup_0/1", "setup_failure"),
            (2, "test/foo.exs:5: PersistenceTest.__ex_unit_setup_all_0/1", "setup_failure"),
            ("timeout", "Assertion with == failed", "timeout"),
            (0, "", "survived"),
            (1, "Unknown worker failure", "harness_failure"),
        ]:
            self.assertEqual(self.classify(code, prefix + suffix)[0], expected)


PROBE_TESTS = {
    "pass": "test \"passes\" do\n    assert Probe.value() == 1\n  end",
    "assertion": "test \"cash stays protected\" do\n    assert Probe.value() == 2\n  end",
    "setup": "setup do\n    raise \"fixture failed\"\n  end\n\n  test \"never runs\", do: :ok",
    "setup_all": "setup_all do\n    raise \"cluster failed\"\n  end\n\n  test \"never runs\", do: :ok",
    "slow": "test \"sleeps\" do\n    Process.sleep(20_000)\n  end",
}


class RealExUnitOutputTest(unittest.TestCase):
    """Classify logs produced by real `mix test` and `mix compile`, not invented strings."""

    @classmethod
    def setUpClass(cls):
        cls.directory = tempfile.TemporaryDirectory(prefix="tijara-classify-")
        cls.work = Path(cls.directory.name) / "probe"
        cls.out = Path(cls.directory.name) / "out"
        (cls.work / "lib").mkdir(parents=True)
        (cls.work / "test").mkdir()
        cls.out.mkdir()
        (cls.work / "mix.exs").write_text(
            'defmodule Probe.MixProject do\n  use Mix.Project\n'
            '  def project, do: [app: :probe, version: "0.0.0", deps: []]\nend\n')
        (cls.work / "lib/probe.ex").write_text("defmodule Probe do\n  def value, do: 1\nend\n")
        (cls.work / "test/test_helper.exs").write_text("ExUnit.start()\n")
        for name, body in PROBE_TESTS.items():
            module = "".join(part.capitalize() for part in name.split("_"))
            (cls.work / f"test/{name}_test.exs").write_text(
                f"defmodule {module}Test do\n  use ExUnit.Case\n\n  {body}\nend\n")
        cls.env = {k: v for k, v in os.environ.items() if not k.startswith(("MIX_", "TIJARA_"))}
        cls.env["MIX_ENV"] = "test"
        compiled = audit.run(cls.work, cls.env, cls.out, "initial-compile", ["mix", "compile"], 120)
        assert compiled["exit"] == 0, Path(compiled["log"]).read_text()

    @classmethod
    def tearDownClass(cls):
        cls.directory.cleanup()

    def classify_test(self, name, timeout=60):
        result = audit.run(self.work, self.env, self.out, name,
                           audit.test_args([f"test/{name}_test.exs"]), timeout)
        return audit.classify(result), result

    def test_test_outcomes(self):
        self.assertEqual(self.classify_test("pass")[0], "survived")
        classification, result = self.classify_test("assertion")
        self.assertEqual(classification, "detected")
        self.assertEqual(result["failing_tests"], ["test cash stays protected (AssertionTest)"])
        self.assertEqual(self.classify_test("setup")[0], "setup_failure")
        self.assertEqual(self.classify_test("setup_all")[0], "setup_failure")
        self.assertEqual(self.classify_test("slow", timeout=5)[0], "timeout")

    def test_mutant_compiles_outside_the_test_budget(self):
        source = self.work / "lib/probe.ex"
        original = source.read_text()
        # Mix compares whole-second mtimes; advance them as the audit does.
        stamp = int(time.time()) + 1
        try:
            audit.touch_source(source, "defmodule Probe do\n  def value, do: missing()\nend\n", stamp)
            fault, classification = audit.mutant(self.work, self.env, self.out, "broken",
                                                 audit.test_args(["test/pass_test.exs"]))
            self.assertEqual(classification, "invalid_compile")
            self.assertEqual(fault["args"], ["mix", "compile"])
            audit.touch_source(source, "defmodule Probe do\n  def value, do: 2\nend\n", stamp + 1)
            fault, classification = audit.mutant(self.work, self.env, self.out, "mutated",
                                                 audit.test_args(["test/pass_test.exs"]))
            self.assertEqual(classification, "detected")
            self.assertNotIn("Compiling", Path(fault["log"]).read_text())
        finally:
            audit.touch_source(source, original, stamp + 2)
            restored = audit.run(self.work, self.env, self.out, "restored", ["mix", "compile"], 120)
            assert restored["exit"] == 0, Path(restored["log"]).read_text()


class CommandLineTest(unittest.TestCase):
    def reject(self, *args):
        with tempfile.TemporaryDirectory() as directory:
            result = subprocess.run([sys.executable, str(Path(__file__).with_name("mutation-audit.py")),
                                     *args, "--out", directory], capture_output=True, text=True)
        self.assertEqual(result.returncode, 2, result.stderr)
        return result.stderr

    def test_invalid_ranges_are_refused_before_any_work(self):
        self.assertIn("--start INDEX", self.reject("replay", "--report", "generated.json"))
        self.assertIn("--report", self.reject("replay", "--start", "3"))
        self.assertIn("count between 1 and 12", self.reject("curated", "--count", "13"))
        self.assertIn("--start must be >= 0", self.reject("curated", "--start", "-1"))

    def test_missing_provenance_base_stops_the_audit(self):
        with tempfile.TemporaryDirectory() as directory:
            repo = Path(directory)
            subprocess.run(["git", "init", "-q", str(repo)], check=True)
            (repo / "source.ex").write_text("line\n")
            subprocess.run(["git", "-C", str(repo), "add", "source.ex"], check=True)
            subprocess.run(["git", "-C", str(repo), "-c", "user.name=t", "-c", "user.email=t@t",
                            "commit", "-qm", "only"], check=True)
            original, audit.ROOT = audit.ROOT, repo
            try:
                with self.assertRaises(SystemExit) as raised:
                    audit.provenance("source.ex", 1)
            finally:
                audit.ROOT = original
        self.assertIn("5ad0399", str(raised.exception))


if __name__ == "__main__":
    unittest.main()
