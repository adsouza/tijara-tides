#!/usr/bin/env python3
"""Exercise release bumps in isolated copies of the real version manifests."""

import io
import json
from pathlib import Path
import runpy
import shutil
import subprocess
import sys
import tempfile
import tomllib
import unittest
from unittest.mock import patch
import xml.etree.ElementTree as ET

from desktop_versions import VERSION_FILES, agreed_version


ROOT = Path(__file__).resolve().parent.parent


class VersionBumpTest(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        for name in VERSION_FILES:
            dest = self.root / name
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT / name, dest)
        scripts = self.root / "scripts"
        scripts.mkdir()
        for name in ("desktop_versions.py", "bump-desktop-version.py", "check-desktop-versions.py"):
            shutil.copy2(ROOT / "scripts" / name, scripts / name)
        self.current = agreed_version(self.root)
        self.major, self.minor, self.patch = map(int, self.current.split("."))

    def contents(self):
        return {name: (self.root / name).read_bytes() for name in VERSION_FILES}

    def bump(self, target, *args):
        return subprocess.run(
            [sys.executable, str(self.root / "scripts/bump-desktop-version.py"),
             target, "--date", "2026-09-29", *args],
            cwd=self.root, capture_output=True, text=True,
        )

    def test_patch_preserves_dependencies_formatting_and_release_history(self):
        before = self.contents()
        result = self.bump("patch")
        self.assertEqual(result.returncode, 0, result.stderr)
        expected = f"{self.major}.{self.minor}.{self.patch + 1}"
        self.assertEqual(agreed_version(self.root), expected)
        checked = subprocess.run(
            [sys.executable, str(self.root / "scripts/check-desktop-versions.py")],
            capture_output=True, text=True,
        )
        self.assertEqual(checked.returncode, 0, checked.stderr)
        for name in ("package.json", "package-lock.json", "src-tauri/tauri.conf.json"):
            original = json.loads(before[name])
            original["version"] = expected
            if name == "package-lock.json":
                original["packages"][""]["version"] = expected
            self.assertEqual(json.loads((self.root / name).read_text()), original)
        for name in ("src-tauri/Cargo.toml", "src-tauri/Cargo.lock"):
            original = tomllib.loads(before[name].decode())
            if name.endswith(".lock"):
                next(p for p in original["package"] if p["name"] == "tijara-tides")["version"] = expected
            else:
                original["package"]["version"] = expected
            self.assertEqual(tomllib.loads((self.root / name).read_text()), original)
        # Keep the edit surgical, including JSON and TOML layout.
        for name in VERSION_FILES[:-1]:
            old_lines = before[name].splitlines(keepends=True)
            new_lines = (self.root / name).read_bytes().splitlines(keepends=True)
            self.assertEqual(len(old_lines), len(new_lines))
            changed = [(old, new) for old, new in zip(old_lines, new_lines) if old != new]
            self.assertEqual(len(changed), 2 if name == "package-lock.json" else 1)
            for old, new in changed:
                self.assertTrue(old.strip().startswith((b'version:', b'"version":', b'version =')))
                self.assertEqual(new, old.replace(self.current.encode(), expected.encode()))
        name = VERSION_FILES[-1]
        previous = ET.fromstring(before[name]).findall("releases/release")
        releases = ET.parse(self.root / name).findall("releases/release")
        self.assertEqual(releases[0].attrib, {"version": expected, "date": "2026-09-29"})
        self.assertEqual([ET.tostring(r).strip() for r in releases[1:]],
                         [ET.tostring(r).strip() for r in previous])

    def test_minor_major_and_explicit_versions(self):
        self.assertEqual(self.bump("minor").returncode, 0)
        self.assertEqual(agreed_version(self.root), f"{self.major}.{self.minor + 1}.0")
        self.assertEqual(self.bump("major").returncode, 0)
        self.assertEqual(agreed_version(self.root), f"{self.major + 1}.0.0")
        explicit = f"{self.major + 2}.3.4"
        self.assertEqual(self.bump(explicit).returncode, 0)
        self.assertEqual(agreed_version(self.root), explicit)
        self.assertEqual(len(ET.parse(self.root / VERSION_FILES[-1]).findall("releases/release")),
                         len(ET.parse(ROOT / VERSION_FILES[-1]).findall("releases/release")) + 3)

    def test_invalid_equal_and_lower_versions_leave_files_unchanged(self):
        before = self.contents()
        for target in ("bogus", "1.2", "01.2.3", "1.2.3-beta", self.current, "0.0.0"):
            with self.subTest(target=target):
                result = self.bump(target)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(self.contents(), before)

    def test_root_package_version_drift_leaves_files_unchanged(self):
        path = self.root / "package-lock.json"
        content = json.loads(path.read_text())
        content["packages"][""]["version"] = "999.0.0"
        path.write_text(json.dumps(content, indent=2) + "\n")
        before = self.contents()
        result = self.bump("patch")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Version declarations disagree", result.stderr)
        self.assertEqual(self.contents(), before)

    def test_invalid_date_and_missing_release_leave_files_unchanged(self):
        before = self.contents()
        result = self.bump("patch", "--date", "2026-02-30")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.contents(), before)
        path = self.root / VERSION_FILES[-1]
        tree = ET.parse(path)
        tree.getroot().remove(tree.getroot().find("releases"))
        tree.write(path)
        before = self.contents()
        result = self.bump("patch")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.contents(), before)

    def test_unexpected_layout_fails_before_writing(self):
        path = self.root / "package-lock.json"
        path.write_text(json.dumps(json.loads(path.read_text()), indent=4) + "\n")
        before = self.contents()
        result = self.bump("patch")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Expected exactly one version field", result.stderr)
        self.assertEqual(self.contents(), before)

    def test_write_failure_restores_prior_and_partially_written_files(self):
        before = self.contents()
        write_text = Path.write_text
        writes = 0

        def fail_second_write(path, content, *args, **kwargs):
            nonlocal writes
            writes += 1
            if writes == 2:
                write_text(path, content[:20], *args, **kwargs)
                raise OSError("simulated failed write")
            return write_text(path, content, *args, **kwargs)

        args = ["bump-desktop-version.py", "patch", "--date", "2026-09-29"]
        stderr = io.StringIO()
        with patch.object(sys, "argv", args), patch.object(Path, "write_text", fail_second_write), patch.object(sys, "stderr", stderr):
            with self.assertRaises(SystemExit) as raised:
                runpy.run_path(str(self.root / "scripts/bump-desktop-version.py"), run_name="__main__")
        self.assertEqual(raised.exception.code, 1)
        self.assertIn("simulated failed write", stderr.getvalue())
        self.assertEqual(self.contents(), before)


if __name__ == "__main__":
    unittest.main()
