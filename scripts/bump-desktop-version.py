#!/usr/bin/env python3
"""Bump all application versions together without changing dependencies or Git."""

import argparse
from datetime import date
from pathlib import Path
import re
import textwrap
import xml.etree.ElementTree as ET

from desktop_versions import VERSION_FILES, agreed_version, next_version


def replace_version(content, pattern, version, name):
    result, count = re.subn(
        pattern, lambda match: match[1] + version + match[2], content,
        flags=re.MULTILINE,
    )
    if count != 1:
        raise ValueError(f"Expected exactly one version field in {name}, found {count}")
    return result


def prepare(root, target, release_date):
    original = {name: (root / name).read_text() for name in VERSION_FILES}
    current = agreed_version(root, original)
    version = next_version(current, target)
    updated = original.copy()
    patterns = {
        "mix.exs": r'(^\s*version: ")[^"]+("\s*,)',
        "package.json": r'(^  "version": ")[^"]+(")',
        "package-lock.json": r'(^  "version": ")[^"]+(")',
        "src-tauri/tauri.conf.json": r'(^  "version": ")[^"]+(")',
        "src-tauri/Cargo.toml": r'(^version = ")[^"]+(")',
        "src-tauri/Cargo.lock": r'(^name = "tijara-tides"\nversion = ")[^"]+(")',
    }
    for name, pattern in patterns.items():
        updated[name] = replace_version(original[name], pattern, version, name)
    updated["package-lock.json"] = replace_version(
        updated["package-lock.json"],
        r'(^    "": \{\n(?:[^\n]*\n)*?      "version": ")[^"]+(")',
        version, "package-lock.json root package",
    )
    name = VERSION_FILES[-1]

    def add_release(match):
        indent, body = match[1], textwrap.dedent(match[2]).strip()
        history = textwrap.indent(body, indent + "  ")
        return (
            f'{indent}<releases>\n'
            f'{indent}  <release version="{version}" date="{release_date.isoformat()}" />\n'
            f'{history}\n{indent}</releases>'
        )

    updated[name], count = re.subn(
        r"^([ \t]*)<releases>(.*?)</releases>", add_release, original[name],
        flags=re.MULTILINE | re.DOTALL,
    )
    if count != 1:
        raise ValueError("Expected exactly one AppStream releases element")
    if agreed_version(root, updated) != version:
        raise ValueError("Updated versions do not match the requested version")
    return current, version, original, updated


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("target", help="patch, minor, major, or an explicit X.Y.Z")
    parser.add_argument("--date", type=date.fromisoformat, default=date.today(),
                        help="AppStream release date YYYY-MM-DD (default: local today)")
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    try:
        current, version, original, updated = prepare(root, args.target, args.date)
        written = []
        try:
            for name, content in updated.items():
                written.append(name)
                (root / name).write_text(content)
            agreed_version(root)
        except Exception:
            for name in written:
                (root / name).write_text(original[name])
            raise
    except (ValueError, KeyError, OSError, ET.ParseError) as error:
        parser.exit(1, f"Version bump failed: {error}\n")
    print(f"Bumped {current} -> {version} in {len(updated)} files; versions agree.")


if __name__ == "__main__":
    main()
