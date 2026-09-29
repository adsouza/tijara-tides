#!/usr/bin/env python3
"""Exercise the release command against isolated real Git repositories."""

import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

from desktop_versions import VERSION_FILES, agreed_version, next_version


ROOT = Path(__file__).resolve().parent.parent


class DesktopReleaseCommandTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.base = Path(temporary.name)
        self.root = self.base / "work"
        self.root.mkdir()
        self.remote = self.base / "origin.git"
        self.env = os.environ.copy()
        for key in list(self.env):
            if key.startswith("GIT_"):
                del self.env[key]
        self.git("init", "-q", "--initial-branch=main")
        self.git("config", "user.name", "Release Test")
        self.git("config", "user.email", "release-test@example.invalid")
        self.git("config", "commit.gpgsign", "false")
        self.git("config", "tag.gpgsign", "false")
        self.git("config", "core.hooksPath", ".git/hooks")
        subprocess.run(["git", "init", "-q", "--bare", "--initial-branch=main", str(self.remote)],
                       env=self.env, check=True)
        self.git("remote", "add", "origin", str(self.remote))
        for name in VERSION_FILES:
            dest = self.root / name
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT / name, dest)
        (self.root / "scripts").mkdir()
        for name in ("desktop_versions.py", "bump-desktop-version.py", "release-desktop.py"):
            shutil.copy2(ROOT / "scripts" / name, self.root / "scripts" / name)
        (self.root / ".gitignore").write_text("scripts/__pycache__/\n")
        self.git("add", ".")
        self.git("commit", "-qm", "Initial version")
        self.git("push", "-q", "-u", "origin", "main")
        self.initial = self.git("rev-parse", "HEAD").stdout.strip()
        self.current = agreed_version(self.root)
        self.version = next_version(self.current, "patch")
        self.tag = "v" + self.version

    def git(self, *args, check=True):
        return subprocess.run(["git", *args], cwd=self.root, env=self.env,
                              capture_output=True, text=True, check=check)

    def remote_ref(self, ref):
        return self.git("--git-dir", str(self.remote), "rev-parse", ref).stdout.strip()

    def release(self, *args):
        return subprocess.run(
            [sys.executable, str(self.root / "scripts/release-desktop.py"),
             *args, "--date", "2026-09-29"], cwd=self.root, env=self.env,
            capture_output=True, text=True,
        )

    def assert_no_release(self):
        self.assertEqual(agreed_version(self.root), self.current)
        self.assertEqual(self.git("rev-parse", "HEAD").stdout.strip(), self.initial)
        self.assertEqual(self.git("tag", "--list", self.tag).stdout, "")

    def hook(self, name, content, remote=False):
        directory = self.remote / "hooks" if remote else self.root / ".git/hooks"
        path = directory / name
        path.write_text("#!/bin/sh\n" + content)
        path.chmod(0o755)

    def test_default_patch_commits_versions_tags_and_pushes_with_hooks(self):
        self.hook("pre-commit", "echo commit >> .git/release-hooks.log\n")
        self.hook("pre-push", "cat >/dev/null\necho push >> .git/release-hooks.log\n")
        result = self.release()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(agreed_version(self.root), self.version)
        commit = self.git("rev-parse", "HEAD").stdout.strip()
        self.assertEqual(self.remote_ref("refs/heads/main"), commit)
        self.assertEqual(self.remote_ref(f"refs/tags/{self.tag}^{{commit}}"), commit)
        self.assertEqual(self.git("cat-file", "-t", f"refs/tags/{self.tag}").stdout.strip(), "tag")
        self.assertEqual(self.git("status", "--porcelain").stdout, "")
        changed = self.git("diff-tree", "--no-commit-id", "--name-only", "-r", "HEAD").stdout.splitlines()
        self.assertEqual(set(changed), set(VERSION_FILES))
        self.assertEqual((self.root / ".git/release-hooks.log").read_text(), "commit\npush\n")

    def test_npm_entrypoint_accepts_explicit_version(self):
        explicit = next_version(self.current, "major")
        result = subprocess.run(
            ["npm", "run", "desktop:release", "--", explicit, "--date", "2026-09-29"],
            cwd=self.root, env=self.env, capture_output=True, text=True,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(agreed_version(self.root), explicit)
        self.assertEqual(self.remote_ref(f"refs/tags/v{explicit}^{{commit}}"), self.remote_ref("main"))

    def test_dirty_checkout_and_other_branch_do_not_bump(self):
        path = self.root / "uncommitted.txt"
        path.write_text("unrelated user change\n")
        result = self.release("patch")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Commit or stash all changes", result.stderr)
        self.assert_no_release()
        path.unlink()
        self.git("checkout", "-qb", "feature")
        result = self.release("patch")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Check out main", result.stderr)
        self.assert_no_release()

    def test_existing_local_and_remote_tags_do_not_bump(self):
        self.git("tag", "-a", self.tag, "-m", "Existing tag")
        result = self.release("patch")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("already exists locally", result.stderr)
        self.assertEqual(agreed_version(self.root), self.current)
        self.git("push", "-q", "origin", self.tag)
        self.git("tag", "-d", self.tag)
        result = self.release("patch")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("already exists on origin", result.stderr)
        self.assertEqual(agreed_version(self.root), self.current)
        self.assertEqual(self.git("rev-parse", "HEAD").stdout.strip(), self.initial)

    def test_behind_main_does_not_bump(self):
        (self.root / "new.txt").write_text("remote change\n")
        self.git("add", "new.txt")
        self.git("commit", "-qm", "Remote main advances")
        self.git("push", "-q", "origin", "main")
        self.git("reset", "--hard", self.initial)
        result = self.release("patch")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("behind or diverges", result.stderr)
        self.assert_no_release()

    def test_rejected_tag_push_does_not_update_either_remote_ref(self):
        self.hook("update", 'case "$1" in refs/tags/*) exit 1;; esac\n', remote=True)
        result = self.release("patch")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(f"git push --atomic origin main {self.tag}", result.stderr)
        self.assertEqual(self.remote_ref("refs/heads/main"), self.initial)
        remote_tag = self.git("--git-dir", str(self.remote), "show-ref", "--verify", "--quiet",
                              f"refs/tags/{self.tag}", check=False)
        self.assertEqual(remote_tag.returncode, 1)
        self.assertEqual(agreed_version(self.root), self.version)
        self.assertEqual(self.git("tag", "--list", self.tag).stdout.strip(), self.tag)
        self.assertEqual(self.git("status", "--porcelain").stdout, "")
        (self.remote / "hooks/update").unlink()
        self.git("push", "--atomic", "origin", "main", self.tag)
        self.assertEqual(self.remote_ref(f"refs/tags/{self.tag}^{{commit}}"), self.remote_ref("main"))

    def test_commit_hook_failure_does_not_tag_or_push(self):
        self.hook("pre-commit", "exit 1\n")
        result = self.release("patch")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("stopped during commit", result.stderr)
        self.assertEqual(self.remote_ref("main"), self.initial)
        self.assertEqual(self.git("tag", "--list", self.tag).stdout, "")
        self.assertEqual(agreed_version(self.root), self.version)


if __name__ == "__main__":
    unittest.main()
