#!/usr/bin/env python3
"""Fail before packaging if a client/server version declaration drifts."""
import json
import re
import tomllib
import xml.etree.ElementTree as ET
from pathlib import Path

root = Path(__file__).resolve().parent.parent
versions = {
    "mix.exs": re.search(r'version: "([^"]+)"', (root / "mix.exs").read_text())[1],
    "package.json": json.loads((root / "package.json").read_text())["version"],
    "package-lock.json": json.loads((root / "package-lock.json").read_text())["version"],
    "tauri.conf.json": json.loads((root / "src-tauri/tauri.conf.json").read_text())["version"],
    "Cargo.toml": tomllib.loads((root / "src-tauri/Cargo.toml").read_text())["package"]["version"],
    "AppStream": ET.parse(root / "packaging/flatpak/io.github.adsouza.tijara-tides.metainfo.xml").find("releases/release").get("version"),
}
lock = tomllib.loads((root / "src-tauri/Cargo.lock").read_text())
versions["Cargo.lock"] = next(p["version"] for p in lock["package"] if p["name"] == "tijara-tides")
if len(set(versions.values())) != 1:
    raise SystemExit(f"Version declarations disagree: {versions}")
print(f"Client and server versions agree: {next(iter(versions.values()))}")
