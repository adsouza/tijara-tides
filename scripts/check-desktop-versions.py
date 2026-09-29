#!/usr/bin/env python3
"""Fail before packaging if a client/server version declaration drifts."""
import argparse
from pathlib import Path

from desktop_versions import agreed_version

root = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--tag", help="Require this release tag to equal v<project version>")
args = parser.parse_args()
try:
    version = agreed_version(root)
except (ValueError, KeyError, OSError) as error:
    raise SystemExit(str(error)) from error
print(f"Client and server versions agree: {version}")
if args.tag is not None and args.tag != f"v{version}":
    raise SystemExit(f"Release tag {args.tag!r} does not match project version v{version}")
