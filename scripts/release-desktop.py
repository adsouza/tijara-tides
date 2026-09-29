#!/usr/bin/env python3
"""Bump, commit, tag, and push a desktop release using the normal Git hooks."""

import argparse
from datetime import date
from pathlib import Path
import subprocess
import sys

from desktop_versions import VERSION_FILES, agreed_version, next_version


ROOT = Path(__file__).resolve().parent.parent


def git(*args, capture=False, check=True):
    return subprocess.run(["git", *args], cwd=ROOT, check=check,
                          capture_output=capture, text=True)


def preflight(target):
    if git("branch", "--show-current", capture=True).stdout.strip() != "main":
        raise ValueError("Check out main before releasing")
    if git("status", "--porcelain", "--untracked-files=normal", capture=True).stdout:
        raise ValueError("Commit or stash all changes before releasing")
    tag = "v" + next_version(agreed_version(ROOT), target)
    local_tag = git("show-ref", "--verify", "--quiet", f"refs/tags/{tag}", check=False)
    if local_tag.returncode == 0:
        raise ValueError(f"Tag {tag} already exists locally")
    if local_tag.returncode != 1:
        local_tag.check_returncode()
    git("fetch", "origin", "main")
    ancestor = git("merge-base", "--is-ancestor", "origin/main", "HEAD", check=False)
    if ancestor.returncode == 1:
        raise ValueError("main is behind or diverges from origin/main; reconcile it before releasing")
    ancestor.check_returncode()
    remote_tag = git("ls-remote", "--exit-code", "--tags", "origin", f"refs/tags/{tag}",
                     capture=True, check=False)
    if remote_tag.returncode == 0:
        raise ValueError(f"Tag {tag} already exists on origin")
    if remote_tag.returncode != 2:
        raise ValueError(f"Cannot check remote tags: {remote_tag.stderr.strip()}")
    return tag


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("target", nargs="?", default="patch",
                        help="patch (default), minor, major, or an explicit X.Y.Z")
    parser.add_argument("--date", type=date.fromisoformat,
                        help="AppStream release date YYYY-MM-DD (default: local today)")
    args = parser.parse_args()
    phase = "preflight"
    tag = None
    try:
        tag = preflight(args.target)
        phase = "version bump"
        command = [sys.executable, str(ROOT / "scripts/bump-desktop-version.py"), args.target]
        if args.date is not None:
            command.extend(["--date", args.date.isoformat()])
        subprocess.run(command, cwd=ROOT, check=True)
        # Read the bump's actual result instead of parsing its human-readable output.
        if "v" + agreed_version(ROOT) != tag:
            raise ValueError("Bumped version does not match the planned release tag")
        phase = "commit"
        git("add", "--", *VERSION_FILES)
        git("commit", "-m", f"Release Tijara Tides {tag}")
        if git("status", "--porcelain", "--untracked-files=normal", capture=True).stdout:
            raise ValueError("Working tree changed during the commit; review it before tagging")
        if "v" + agreed_version(ROOT) != tag:
            raise ValueError("Committed version does not match the release tag")
        phase = "tag"
        git("tag", "-a", tag, "-m", f"Tijara Tides {tag}")
        phase = "push"
        git("push", "--atomic", "origin", "main", tag)
    except (ValueError, KeyError, OSError, subprocess.CalledProcessError) as error:
        print(f"Desktop release stopped during {phase}: {error}", file=sys.stderr)
        if phase == "push":
            print(f"The release commit and tag are kept locally. Retry without bumping again:\n"
                  f"  git push --atomic origin main {tag}", file=sys.stderr)
        elif phase in ("commit", "tag"):
            print("The version changes are kept locally; resolve the Git failure before continuing.",
                  file=sys.stderr)
        parser.exit(1)
    print(f"Pushed main and {tag}; GitHub Actions will build and publish the desktop packages.")


if __name__ == "__main__":
    main()
