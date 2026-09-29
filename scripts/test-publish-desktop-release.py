#!/usr/bin/env python3
"""Exercise publishing failures and retries with local packages and a fake gh."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from desktop_versions import VERSION_FILES, agreed_version


ROOT = Path(__file__).resolve().parent.parent
FAKE_GH = '''#!/usr/bin/env python3
import json, os
from pathlib import Path
import sys
args = sys.argv[1:]
path = Path(os.environ["RELEASE_TEST_STATE"])
state = json.loads(path.read_text())
state["calls"].append(args)
def save():
    path.write_text(json.dumps(state))
def fail(message):
    save()
    print(message, file=sys.stderr)
    sys.exit(1)
if args[0] == "api":
    print(state.get("remote_commit", os.environ["RELEASE_COMMIT"]))
elif args[:2] == ["release", "view"]:
    if not state.get("exists"):
        fail("release not found")
    print("true" if state["draft"] else "false")
elif args[:2] == ["release", "create"]:
    if state.get("failure") == "create":
        fail("create failed")
    assert "--draft" in args and "--verify-tag" in args
    state.update(exists=True, draft=True)
elif args[:2] == ["release", "upload"]:
    assert state["draft"]
    state["assets"] = [Path(a).name for a in args[3:] if a != "--clobber"]
    if state.get("failure") == "upload":
        state["assets"] = state["assets"][:1]
        fail("upload failed")
elif args[:2] == ["release", "edit"]:
    assert "--draft=false" in args
    if state.get("failure") == "publish":
        fail("publish failed")
    state["draft"] = False
else:
    fail("unexpected gh call: " + repr(args))
save()
'''


class DesktopReleaseTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        for name in VERSION_FILES:
            dest = self.root / name
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT / name, dest)
        scripts = self.root / "scripts"
        scripts.mkdir()
        for name in ("desktop_versions.py", "check-desktop-versions.py", "publish-desktop-release.sh"):
            shutil.copy2(ROOT / "scripts" / name, scripts / name)
        self.tag = "v" + agreed_version(self.root)
        self.artifacts = self.root / "dist/release"
        self.artifacts.mkdir(parents=True)
        self.names = ["Tijara Tides_amd64.deb", "tijara-tides.flatpak",
                      "Tijara Tides_aarch64.dmg", "Tijara-Tides.app.zip"]
        for name in self.names:
            (self.artifacts / name).write_bytes(b"test package")
        binary = self.root / "bin"
        binary.mkdir()
        gh = binary / "gh"
        gh.write_text(FAKE_GH)
        gh.chmod(0o755)
        self.state_path = self.root / "gh-state.json"
        self.state_path.write_text(json.dumps({"exists": False, "calls": []}))
        self.env = os.environ.copy()
        self.env.update(PATH=str(binary) + os.pathsep + self.env["PATH"],
                        GH_REPO="test/tijara-tides", GH_TOKEN="local-test-token",
                        RELEASE_COMMIT="a" * 40, RELEASE_TEST_STATE=str(self.state_path))

    def state(self):
        return json.loads(self.state_path.read_text())

    def configure(self, **values):
        state = self.state()
        state.update(values)
        self.state_path.write_text(json.dumps(state))

    def publish(self, tag=None):
        return subprocess.run(
            ["bash", str(self.root / "scripts/publish-desktop-release.sh"),
             tag or self.tag, "dist/release"], cwd=self.root,
            env=self.env, capture_output=True, text=True,
        )

    def test_publishes_all_four_packages_only_after_upload(self):
        result = self.publish()
        self.assertEqual(result.returncode, 0, result.stderr)
        state = self.state()
        self.assertFalse(state["draft"])
        self.assertEqual(sorted(state["assets"]), sorted(self.names))
        self.assertEqual([call[:2] for call in state["calls"] if call[0] == "release"],
                         [["release", "view"], ["release", "create"],
                          ["release", "upload"], ["release", "edit"]])

    def test_failed_upload_stays_draft_and_retry_resumes(self):
        self.configure(failure="upload")
        result = self.publish()
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(self.state()["draft"])
        self.assertEqual(len(self.state()["assets"]), 1)
        self.assertFalse(any(call[:2] == ["release", "edit"] for call in self.state()["calls"]))
        self.configure(failure=None, calls=[])
        result = self.publish()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(self.state()["draft"])
        self.assertEqual(sorted(self.state()["assets"]), sorted(self.names))
        self.assertFalse(any(call[:2] == ["release", "create"] for call in self.state()["calls"]))

    def test_create_and_publish_failures_do_not_publish(self):
        self.configure(failure="create")
        self.assertNotEqual(self.publish().returncode, 0)
        self.assertFalse(self.state()["exists"])
        self.assertFalse(any(call[:2] == ["release", "upload"] for call in self.state()["calls"]))
        self.configure(failure="publish", calls=[])
        self.assertNotEqual(self.publish().returncode, 0)
        self.assertTrue(self.state()["draft"])

    def test_published_release_is_never_replaced(self):
        self.configure(exists=True, draft=False, assets=["original.deb"])
        result = self.publish()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("already published", result.stderr)
        self.assertEqual(self.state()["assets"], ["original.deb"])
        self.assertFalse(any(call[:2] in (["release", "upload"], ["release", "edit"])
                             for call in self.state()["calls"]))

    def test_missing_duplicate_and_empty_packages_fail_before_network(self):
        path = self.artifacts / self.names[-1]
        path.unlink()
        self.assertNotEqual(self.publish().returncode, 0)
        self.assertEqual(self.state()["calls"], [])
        path.write_bytes(b"")
        self.assertNotEqual(self.publish().returncode, 0)
        self.assertEqual(self.state()["calls"], [])
        path.write_bytes(b"test package")
        (self.artifacts / "extra.deb").write_bytes(b"extra")
        self.assertNotEqual(self.publish().returncode, 0)
        self.assertEqual(self.state()["calls"], [])

    def test_mismatching_tag_fails_before_network(self):
        result = self.publish("v999.0.0")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("does not match project version", result.stderr)
        self.assertEqual(self.state()["calls"], [])

    def test_retargeted_remote_tag_does_not_create_release(self):
        self.configure(remote_commit="b" * 40)
        result = self.publish()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("no longer points to the built commit", result.stderr)
        self.assertFalse(self.state()["exists"])
        self.assertEqual(len(self.state()["calls"]), 1)


if __name__ == "__main__":
    unittest.main()
