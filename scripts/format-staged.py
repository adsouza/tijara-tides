#!/usr/bin/env python3
"""Format staged Elixir/HEEx without staging unrelated working-tree edits."""

import os
from pathlib import Path
import subprocess
import sys
import tempfile


def run(*args, **kwargs):
    return subprocess.run(args, check=True, stdout=subprocess.PIPE, **kwargs).stdout


def main():
    paths = run("git", "diff", "--cached", "--name-only", "--diff-filter=ACMR", "-z")
    changes = []
    for raw_path in filter(None, paths.split(b"\0")):
        name = os.fsdecode(raw_path)
        path = Path(name)
        if path.suffix not in {".ex", ".exs", ".heex"}:
            continue
        entry = run("git", "ls-files", "--stage", "-z", "--", name)
        mode, oid, stage = entry.split(b"\t", 1)[0].split()
        if mode not in {b"100644", b"100755"} or stage != b"0":
            continue
        original = run("git", "cat-file", "blob", oid.decode())
        formatted = run(
            "mix", "format", "--no-compile", "--stdin-filename", name, "-",
            input=original,
        )
        if formatted == original:
            continue
        if path.is_symlink() or not path.is_file():
            raise RuntimeError(f"{name}: working file is missing or no longer a regular file")
        working = path.read_bytes()
        merged = formatted
        if working != original:
            with tempfile.TemporaryDirectory(prefix="tijara-format-") as directory:
                files = [Path(directory) / item for item in ("working", "staged", "formatted")]
                for file, content in zip(files, (working, original, formatted)):
                    file.write_bytes(content)
                result = subprocess.run(
                    ["git", "merge-file", "-p", *map(str, files)],
                    stdout=subprocess.PIPE,
                )
                if result.returncode:
                    raise RuntimeError(
                        f"{name}: formatting overlaps unstaged edits; reconcile or stage "
                        "those edits before committing. No files were changed."
                    )
                merged = result.stdout
        changes.append((path, raw_path, mode, working, merged, formatted))

    # Plan every merge before touching files; update all index entries together.
    entries = []
    for _, raw_path, mode, _, _, formatted in changes:
        oid = run("git", "hash-object", "-w", "--stdin", input=formatted).strip()
        entries.append(mode + b" " + oid + b"\t" + raw_path + b"\0")
    written = []
    try:
        for path, _, _, working, merged, _ in changes:
            written.append((path, working))
            path.write_bytes(merged)
        if entries:
            run("git", "update-index", "-z", "--index-info", input=b"".join(entries))
    except Exception:
        for path, working in written:
            path.write_bytes(working)
        raise
    if changes:
        print(f"Pre-commit: formatted {len(changes)} staged Elixir/HEEx file(s).")


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, OSError, subprocess.CalledProcessError) as error:
        print(f"Pre-commit formatting failed: {error}", file=sys.stderr)
        sys.exit(1)
