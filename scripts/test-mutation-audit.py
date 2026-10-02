#!/usr/bin/env python3
"""Detection classification is a safety contract, not an exit-code score."""
import importlib.util
from pathlib import Path
import sys
import tempfile
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
            (2, "test/foo.exs:33 setup_all/1", "setup_failure"),
            ("timeout", "Assertion with == failed", "timeout"),
            (0, "", "survived"),
            (1, "Unknown worker failure", "harness_failure"),
        ]:
            self.assertEqual(self.classify(code, prefix + suffix)[0], expected)


if __name__ == "__main__":
    unittest.main()
