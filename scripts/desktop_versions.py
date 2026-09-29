"""Read the version declarations shared by the server and desktop packages."""

import json
import re
import tomllib
import xml.etree.ElementTree as ET
from pathlib import Path


VERSION_FILES = (
    "mix.exs",
    "package.json",
    "package-lock.json",
    "src-tauri/tauri.conf.json",
    "src-tauri/Cargo.toml",
    "src-tauri/Cargo.lock",
    "packaging/flatpak/io.github.adsouza.tijara-tides.metainfo.xml",
)


def version_parts(version):
    if not re.fullmatch(r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)", version):
        raise ValueError(f"Expected a release version X.Y.Z, got {version!r}")
    return tuple(int(part) for part in version.split("."))


def next_version(current, target):
    major, minor, patch = version_parts(current)
    increments = {
        "patch": (major, minor, patch + 1),
        "minor": (major, minor + 1, 0),
        "major": (major + 1, 0, 0),
    }
    parts = increments[target] if target in increments else version_parts(target)
    if parts <= (major, minor, patch):
        raise ValueError(f"New version must be greater than {current}")
    return ".".join(str(part) for part in parts)


def read_versions(root: Path, contents=None):
    def read(name):
        return contents[name] if contents is not None else (root / name).read_text()

    mix = re.search(r'^\s*version: "([^"]+)"', read("mix.exs"), re.MULTILINE)
    if mix is None:
        raise ValueError("Missing project version in mix.exs")
    npm_lock = json.loads(read("package-lock.json"))
    cargo_lock = tomllib.loads(read("src-tauri/Cargo.lock"))
    packages = [p for p in cargo_lock["package"] if p["name"] == "tijara-tides"]
    if len(packages) != 1:
        raise ValueError("Expected one tijara-tides package in Cargo.lock")
    release = ET.fromstring(read(VERSION_FILES[-1])).find("releases/release")
    if release is None or not release.get("version"):
        raise ValueError("Missing AppStream release version")
    return {
        "mix.exs": mix[1],
        "package.json": json.loads(read("package.json"))["version"],
        "package-lock.json": npm_lock["version"],
        "package-lock.json packages['']": npm_lock["packages"][""]["version"],
        "tauri.conf.json": json.loads(read("src-tauri/tauri.conf.json"))["version"],
        "Cargo.toml": tomllib.loads(read("src-tauri/Cargo.toml"))["package"]["version"],
        "Cargo.lock": packages[0]["version"],
        "AppStream": release.get("version"),
    }


def agreed_version(root: Path, contents=None):
    versions = read_versions(root, contents)
    if len(set(versions.values())) != 1:
        raise ValueError(f"Version declarations disagree: {versions}")
    return next(iter(versions.values()))
