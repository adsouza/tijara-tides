#!/usr/bin/env python3
"""Exercise validation selection and push boundaries in disposable Git repositories."""
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
SCOPE = ROOT / "scripts/validation_scope.py"


class ValidationScopeTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="tijara-validation-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / "repo"
        self.root.mkdir()
        self.git("init", "-q", "-b", "main")
        self.git("config", "user.name", "Validation tests")
        self.git("config", "user.email", "validation@example.invalid")
        self.git("config", "core.hooksPath", ".disabled-hooks")
        self.git("config", "commit.gpgsign", "false")
        self.write("README.md", "Readme\n")
        self.write("docs/note.md", "Documentation\n")
        self.write("lib/example.ex", "original\n")
        self.commit()
        self.base = self.git("rev-parse", "HEAD").decode().strip()

    def git(self, *args):
        return subprocess.check_output(["git", *args], cwd=self.root, stderr=subprocess.PIPE)

    def write(self, name, content):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)
        return path

    def commit(self):
        self.git("add", ".")
        self.git("commit", "--allow-empty", "-qm", "Fixture")

    def scope(self, *args):
        result = subprocess.run(
            [sys.executable, str(SCOPE), *args], cwd=self.root,
            capture_output=True, text=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout.strip()

    def test_staged_and_unstaged_documentation(self):
        self.write("docs/note.md", "Staged\n")
        self.git("add", "docs/note.md")
        self.write("README.md", "Unstaged\n")
        self.assertEqual(self.scope("--base", self.base), "docs")

    def test_all_documentary_commits_and_deletions(self):
        self.write("docs/nested/note with spaces\nand newline.md", "New\n")
        self.commit()
        self.git("rm", "README.md")
        self.commit()
        self.assertEqual(self.scope("--base", self.base), "docs")

    def test_code_in_earlier_commit_requires_full_checks(self):
        self.write("lib/example.ex", "changed\n")
        self.commit()
        self.write("docs/note.md", "Latest docs\n")
        self.commit()
        self.assertEqual(self.scope("--base", self.base), "full")

    def test_reverted_code_still_requires_full_checks(self):
        self.write("lib/example.ex", "changed\n")
        self.commit()
        self.write("lib/example.ex", "original\n")
        self.commit()
        self.write("docs/note.md", "Latest docs\n")
        self.commit()
        self.assertEqual(self.git("diff", self.base, "HEAD", "--", "lib"), b"")
        self.assertEqual(self.scope("--base", self.base), "full")

    def test_all_push_bases_are_checked(self):
        self.write("lib/example.ex", "changed\n")
        self.commit()
        newer = self.git("rev-parse", "HEAD").decode().strip()
        self.write("docs/note.md", "Docs\n")
        self.commit()
        self.assertEqual(self.scope("--base", newer), "docs")
        self.assertEqual(self.scope("--base", newer, "--base", self.base), "full")

    def test_non_documentary_working_and_index_changes(self):
        for staged in (False, True):
            with self.subTest(staged=staged):
                self.write("lib/example.ex", "changed\n")
                if staged:
                    self.git("add", "lib/example.ex")
                self.assertEqual(self.scope("--base", self.base), "full")

    def test_unknown_new_branch_and_missing_upstream_are_full(self):
        self.write("docs/note.md", "Docs\n")
        for args in ([], ["--base", "missing"], ["--base", "0" * 40]):
            with self.subTest(args=args):
                self.assertEqual(self.scope(*args), "full")

    def test_non_ancestor_base_is_full(self):
        self.git("switch", "-qc", "other")
        self.write("docs/note.md", "Other branch\n")
        self.commit()
        other = self.git("rev-parse", "HEAD").decode().strip()
        self.git("switch", "-q", "main")
        self.write("docs/note.md", "Main\n")
        self.assertEqual(self.scope("--base", other), "full")

    def test_upstream_is_default_base(self):
        self.git("remote", "add", "origin", str(self.root))
        self.git("update-ref", "refs/remotes/origin/main", self.base)
        self.git("branch", "--set-upstream-to=origin/main")
        self.write("docs/note.md", "Docs\n")
        self.assertEqual(self.scope(), "docs")

    def test_policy_and_markdown_outside_documentation_are_full(self):
        for name in ("AGENTS.md", "CLAUDE.md", "assets/note.md", "docs/data.json"):
            with self.subTest(name=name):
                path = self.write(name, "Changed\n")
                self.git("add", name)
                self.assertEqual(self.scope("--base", self.base), "full")
                self.git("rm", "-f", name)
                self.assertFalse(path.exists())

    def test_executable_markdown_is_full(self):
        self.git("update-index", "--chmod=+x", "docs/note.md")
        self.assertEqual(self.scope("--base", self.base), "full")

    def test_symlink_markdown_is_full(self):
        (self.root / "docs/link.md").symlink_to("note.md")
        self.git("add", "docs/link.md")
        self.assertEqual(self.scope("--base", self.base), "full")

    def test_rename_from_code_to_markdown_is_full(self):
        self.git("mv", "lib/example.ex", "docs/example.md")
        self.commit()
        self.assertEqual(self.scope("--base", self.base), "full")

    def test_merge_history_cannot_hide_code(self):
        self.git("switch", "-qc", "feature")
        self.write("lib/example.ex", "feature\n")
        self.commit()
        self.git("switch", "-q", "main")
        self.write("docs/note.md", "Docs\n")
        self.commit()
        self.git("merge", "-q", "--no-ff", "feature", "-m", "Merge")
        self.assertEqual(self.scope("--base", self.base), "full")

    def test_documentation_only_merge_is_documentary(self):
        self.git("switch", "-qc", "feature")
        self.write("README.md", "Feature docs\n")
        self.commit()
        self.git("switch", "-q", "main")
        self.write("docs/note.md", "Main docs\n")
        self.commit()
        self.git("merge", "-q", "--no-ff", "feature", "-m", "Merge")
        self.assertEqual(self.scope("--base", self.base), "docs")

    def test_untracked_and_empty_changes_are_full(self):
        self.assertEqual(self.scope("--base", self.base), "full")
        self.write("docs/new.md", "New\n")
        self.assertEqual(self.scope("--base", self.base), "full")
        self.git("add", "docs/new.md")
        self.assertEqual(self.scope("--base", self.base), "docs")
        self.assertEqual(self.scope("--base", self.base, "--full"), "full")

    def test_whitespace_checks_history_index_and_working_tree(self):
        for location in ("history", "index", "working"):
            with self.subTest(location=location):
                self.write("docs/note.md", "Trailing whitespace \n")
                if location != "working":
                    self.git("add", "docs/note.md")
                if location == "history":
                    self.commit()
                result = subprocess.run(
                    [sys.executable, str(SCOPE), "--base", self.base, "--check-whitespace"],
                    cwd=self.root, capture_output=True,
                )
                self.assertNotEqual(result.returncode, 0)
                self.write("docs/note.md", "Clean\n")
                self.commit()
                self.base = self.git("rev-parse", "HEAD").decode().strip()

    def prepare_hook(self):
        self.log = Path(self.temp.name) / "checks.log"
        self.write("scripts/check-local.sh", '#!/bin/sh\nprintf "%s\\n" "$@" > "$CHECK_LOG"\n').chmod(0o755)
        self.commit()
        self.base = self.git("rev-parse", "HEAD").decode().strip()
        self.write("docs/note.md", "Docs\n")
        self.commit()
        return self.git("rev-parse", "HEAD").decode().strip()

    def push_hook(self, payload):
        return subprocess.run(
            ["bash", str(ROOT / ".githooks/pre-push")], cwd=self.root,
            input=payload, text=True, capture_output=True,
            env={**os.environ, "CHECK_LOG": str(self.log)},
        )

    def test_push_hook_passes_every_remote_base(self):
        head = self.prepare_hook()
        result = self.push_hook(
            f"refs/heads/main {head} refs/heads/main {self.base}\n"
            f"refs/heads/main {head} refs/heads/other {head}\n"
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.log.read_text().splitlines(), ["--base", self.base, "--base", head])

    def test_push_hook_rejects_dirty_or_other_checked_out_commit(self):
        head = self.prepare_hook()
        payload = f"refs/heads/main {head} refs/heads/main {self.base}\n"
        self.write("docs/note.md", "Dirty\n")
        self.assertNotEqual(self.push_hook(payload).returncode, 0)
        self.assertFalse(self.log.exists())
        self.git("restore", "docs/note.md")
        self.assertNotEqual(self.push_hook(payload.replace(head, self.base)).returncode, 0)
        self.assertFalse(self.log.exists())

    def test_tag_pushes_are_full_and_deletions_do_not_run_checks(self):
        head = self.prepare_hook()
        result = self.push_hook(f"refs/tags/v1 {head} refs/tags/v1 {self.base}\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.log.read_text().splitlines(), ["--full"])
        self.log.unlink()
        self.assertEqual(self.push_hook(f"(delete) {'0' * 40} refs/heads/other {head}\n").returncode, 0)
        self.assertFalse(self.log.exists())

    def test_documentation_pipeline_runs_only_documentation_gates(self):
        self.log = Path(self.temp.name) / "checks.log"
        (self.root / "scripts").mkdir()
        for name in ("check-local.sh", "validation_scope.py"):
            shutil.copyfile(ROOT / "scripts" / name, self.root / "scripts" / name)
        self.write("scripts/check-generated.py", 'import os, sys\nwith open(os.environ["CHECK_LOG"], "a") as log: log.write("generated " + " ".join(sys.argv[1:]) + "\\n")\n')
        self.commit()
        self.base = self.git("rev-parse", "HEAD").decode().strip()
        self.write("docs/note.md", "Docs\n")
        # Export a shell function so the mock survives check-local's PATH setup.
        command = 'mix() { printf "mix %s\\n" "$*" >> "$CHECK_LOG"; }; export -f mix; exec bash scripts/check-local.sh --base "$1"'
        result = subprocess.run(
            ["bash", "-c", command, "checks", self.base], cwd=self.root,
            capture_output=True, text=True, env={**os.environ, "CHECK_LOG": str(self.log)},
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.log.read_text().splitlines(), ["generated --docs-only", "mix test test/docs"])


class GeneratedDocumentationTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="tijara-generated-docs-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / "scripts").mkdir()
        (self.root / "docs").mkdir()
        shutil.copyfile(ROOT / "scripts/check-generated.py", self.root / "scripts/check-generated.py")
        for generator, artifact in (
            ("gen-ports-roster.py", "ports.md"),
            ("gen-ship-instructions.py", "ship-instructions.md"),
            ("gen-ux-inventory.py", "ux-inventory.md"),
        ):
            (self.root / "docs" / artifact).write_text("Generated\n")
            (self.root / "scripts" / generator).write_text(
                f'from pathlib import Path\n(Path(__file__).resolve().parent.parent / "docs/{artifact}").write_text("Generated\\n")\n'
            )
        (self.root / "scripts/gen-game-data.py").write_text('raise SystemExit("Runtime catalogue invoked")\n')

    def run_check(self, *args):
        return subprocess.run(
            [sys.executable, str(self.root / "scripts/check-generated.py"), *args],
            capture_output=True, text=True,
        )

    def test_documentation_mode_does_not_run_runtime_catalogue(self):
        result = self.run_check("--docs-only")
        self.assertEqual(result.returncode, 0, result.stderr)
        result = self.run_check()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Runtime catalogue invoked", result.stderr)

    def test_stale_generated_document_fails_without_changing_checkout(self):
        path = self.root / "docs/ports.md"
        path.write_text("Hand-edited\n")
        result = self.run_check("--docs-only")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("docs/ports.md", result.stderr)
        self.assertEqual(path.read_text(), "Hand-edited\n")


if __name__ == "__main__":
    unittest.main()
