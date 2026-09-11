#!/usr/bin/env python3
"""Isolated Git integration tests for staged formatting (no game database)."""

import os
from pathlib import Path
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).with_name("format-staged.py").resolve()


class StagedFormattingTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.env = os.environ.copy()
        for key in list(self.env):
            if key.startswith("GIT_"):
                del self.env[key]
        self.git("init", "-q")
        binary = self.root / "bin"
        binary.mkdir()
        formatter = binary / "mix"
        formatter.write_text(
            "#!/usr/bin/env python3\nimport sys\n"
            "data = sys.stdin.read()\n"
            "if 'INVALID' in data: sys.exit(1)\n"
            "sys.stdout.write(data.replace('x=1', 'x = 1'))\n"
        )
        formatter.chmod(0o755)
        self.env["PATH"] = str(binary) + os.pathsep + self.env["PATH"]

    def git(self, *args):
        return subprocess.check_output(["git", *args], cwd=self.root, env=self.env)

    def stage(self, name, content):
        (self.root / name).write_text(content)
        self.git("add", "--", name)

    def format(self):
        return subprocess.run(
            ["python3", str(SCRIPT)], cwd=self.root, env=self.env,
            capture_output=True,
        )

    def test_formats_staged_file_with_spaces_and_preserves_unstaged_files(self):
        self.stage("some file.ex", "x=1\n")
        (self.root / "other.ex").write_text("x=1\n")
        self.assertEqual(self.format().returncode, 0)
        self.assertEqual(self.git("show", ":some file.ex"), b"x = 1\n")
        self.assertEqual((self.root / "some file.ex").read_bytes(), b"x = 1\n")
        self.assertEqual((self.root / "other.ex").read_bytes(), b"x=1\n")

    def test_partial_staging_preserves_independent_edit(self):
        original = "x=1\na\nb\nc\nd\ne\nf\n"
        self.stage("sample.ex", original)
        working = original + "unstaged\n"
        (self.root / "sample.ex").write_text(working)
        self.assertEqual(self.format().returncode, 0)
        self.assertEqual(self.git("show", ":sample.ex"), original.replace("x=1", "x = 1").encode())
        self.assertEqual((self.root / "sample.ex").read_text(), working.replace("x=1", "x = 1"))

    def test_overlap_leaves_all_files_and_index_unchanged(self):
        self.stage("a.ex", "x=1\n")
        self.stage("z.ex", "x=1\n")
        (self.root / "z.ex").write_text("x=2\n")
        self.assertNotEqual(self.format().returncode, 0)
        self.assertEqual(self.git("show", ":a.ex"), b"x=1\n")
        self.assertEqual((self.root / "a.ex").read_text(), "x=1\n")
        self.assertEqual(self.git("show", ":z.ex"), b"x=1\n")
        self.assertEqual((self.root / "z.ex").read_text(), "x=2\n")

    def test_formatter_failure_does_not_apply_prior_changes(self):
        self.stage("a.ex", "x=1\n")
        self.stage("z.ex", "INVALID\n")
        self.assertNotEqual(self.format().returncode, 0)
        self.assertEqual(self.git("show", ":a.ex"), b"x=1\n")
        self.assertEqual((self.root / "a.ex").read_text(), "x=1\n")


if __name__ == "__main__":
    unittest.main()
