#!/usr/bin/env python3
"""Regenerate docs/music-credits.md from priv/audio/music.json."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
manifest = json.loads((ROOT / "priv/audio/music.json").read_text())
lines = [
    "# Music credits",
    "",
    "Generated from `priv/audio/music.json` by `scripts/gen-music-credits.py`; do",
    "not edit by hand. The game's music credits page shows the same entries.",
    "",
]
for palette in manifest["palettes"]:
    lines += [f"## {palette['name']}", ""]
    for role in ("port", "voyage"):
        for slug in palette[role]:
            track = manifest["tracks"][slug]
            lines += [
                f"### {track['title']}",
                "",
                f"- Role: {role}",
                f"- Credit: {track['credit']}",
                f"- Source: <{track['source_url']}>",
                f"- License: [{track['licence']}]({track['licence_url']})",
                f"- Edits: {track['edits']}",
            ]
            for notice in track["notices"]:
                lines.append(f"- Supplied notice: `priv/audio/{notice['file']}` ({notice['name']})")
            lines.append("")
(ROOT / "docs/music-credits.md").write_text("\n".join(lines))
