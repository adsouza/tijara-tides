#!/usr/bin/env python3
"""Select documentation checks only for a known, entirely documentary range."""
import argparse
import os
from pathlib import PurePosixPath
import subprocess
import sys


def git(*args):
    return subprocess.check_output(["git", *args], stderr=subprocess.PIPE)


def documentary(raw):
    """Read NUL-delimited raw diffs; renames must be expanded into delete/add."""
    fields = raw.split(b"\0")
    if fields[-1] != b"":
        raise ValueError("unterminated diff")
    fields.pop()
    if len(fields) % 2:
        raise ValueError("unexpected diff shape")
    paths = []
    for header, path in zip(fields[::2], fields[1::2]):
        parts = header.split()
        if len(parts) != 5 or not parts[0].startswith(b":"):
            raise ValueError("unexpected diff record")
        modes = (parts[0][1:], parts[1])
        name = os.fsdecode(path)
        allowed = name in {"README.md", "ARCHITECTURE.md"} or (
            name.startswith("docs/") and PurePosixPath(name).suffix == ".md"
        )
        if not allowed or any(mode not in {b"000000", b"100644"} for mode in modes):
            return False, []
        paths.append(name)
    return True, paths


def select(bases, force_full=False):
    if force_full:
        return "full", [], "explicit full validation"
    try:
        head = git("rev-parse", "--verify", "HEAD^{commit}").decode().strip()
        if not bases:
            bases = [git("rev-parse", "--verify", "@{upstream}^{commit}").decode().strip()]
        resolved = []
        commits = set()
        for base in bases:
            base = git("rev-parse", "--verify", f"{base}^{{commit}}").decode().strip()
            git("merge-base", "--is-ancestor", base, head)
            resolved.append(base)
            commits.update(git("rev-list", f"{base}..{head}").decode().splitlines())

        changed = False
        for commit in sorted(commits):
            valid, paths = documentary(git(
                "diff-tree", "--root", "--no-commit-id", "-r", "-m",
                "--no-renames", "--raw", "-z", commit,
            ))
            if not valid:
                return "full", resolved, "outgoing history includes non-documentation changes"
            changed |= bool(paths)

        for options in ([], ["--cached"]):
            valid, paths = documentary(git("diff", "--no-ext-diff", "--no-renames", "--raw", "-z", *options))
            if not valid:
                return "full", resolved, "working tree or index includes non-documentation changes"
            changed |= bool(paths)
        if git("ls-files", "--others", "--exclude-standard", "-z"):
            return "full", resolved, "untracked files; stage new documentation before selection"
        if not changed:
            return "full", resolved, "no changes to classify"
        return "docs", resolved, "only regular Markdown in approved documentation paths"
    except (subprocess.CalledProcessError, OSError, ValueError):
        return "full", [], "change range or file metadata could not be established"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base", action="append", default=[], help="Known outgoing base; repeat for multiple refs.")
    parser.add_argument("--full", action="store_true", help="Always select the full suite.")
    parser.add_argument("--check-whitespace", action="store_true", help="Check the selected documentation range, index and working tree.")
    args = parser.parse_args()
    scope, bases, reason = select(args.base, args.full)
    if args.check_whitespace:
        if scope != "docs":
            raise SystemExit("Documentation scope is unavailable or changed; rerun validation.")
        for base in bases:
            subprocess.run(["git", "diff", "--no-ext-diff", "--check", base, "HEAD"], check=True)
        for options in ([], ["--cached"]):
            subprocess.run(["git", "diff", "--no-ext-diff", "--check", *options], check=True)
    else:
        print(f"Validation scope: {scope} ({reason})", file=sys.stderr)
        print(scope)


if __name__ == "__main__":
    main()
