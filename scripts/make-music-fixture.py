#!/usr/bin/env python3
"""Regenerate the synthetic test soundtrack in priv/audio/fixtures.

Four 40-second tones run through the real preparation pipeline, and every
approval is recorded against them, so tests and the browser contract exercise
production's manifest format, availability gate and serving path. These
records are not listening decisions.
"""
import importlib.util
import json
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("prepare_music", ROOT / "scripts/prepare-music.py")
prepare_music = importlib.util.module_from_spec(spec)
spec.loader.exec_module(prepare_music)

TONES = {
    "east-port": (440, "East Harbour Tone", 0),
    "east-voyage": (494, "East Passage Tone", 0),
    "west-port": (660, "West Harbour Tone", 0),
    "west-voyage": (740, "West Passage Tone", 2),
}
RECIPE = {"strategy": "whole-recording", "settle_s": 3, "fade_out_s": 5, "fade_in_s": 2,
          "silence_s": 1, "crossfade_s": 2, "silence_floor_db": -60, "loudness_lufs": -20,
          "true_peak_dbtp": -1, "codec": "opus", "bitrate_kbps": 6}
PALETTES = [
    {"id": "east", "name": "East", "ports": ["Guangzhou", "Shanghai", "Shenzhen", "Hong Kong", "Jakarta",
                                             "Singapore", "Ho Chi Minh City", "Manila"],
     "port": ["east-port"], "voyage": ["east-voyage"]},
    {"id": "west", "name": "West", "ports": ["Tangier", "Valencia", "Athens", "Hamburg", "Rotterdam"],
     "port": ["west-port"], "voyage": ["west-voyage"]},
]
NOTE = "Synthetic test tone; not a listening decision."


def approve_all(manifest):
    recipe, tracks = manifest["recipe"], manifest["tracks"]
    approved = {"decision": "approved", "date": "2026-10-12", "notes": NOTE}
    records = {slug: {"recording": {**approved, "source_sha256": t["source_sha256"]},
                      "playback": {**approved, "output_sha256": t["output_sha256"],
                                   "entry_s": t["entry_s"], "recipe": recipe}}
               for slug, t in tracks.items()}
    handoffs = [{**approved, "kind": "port-to-voyage", "from": port, "to": voyage,
                 "from_output_sha256": tracks[port]["output_sha256"],
                 "to_output_sha256": tracks[voyage]["output_sha256"],
                 "to_entry_s": tracks[voyage]["entry_s"], "recipe": recipe}
                for palette in manifest["palettes"] for port in palette["port"] for voyage in palette["voyage"]]
    for source, target in (("east-voyage", "west-voyage"), ("west-voyage", "east-voyage")):
        handoffs.append({**approved, "kind": "voyage-handoff", "from": source, "to": target,
                         "from_output_sha256": tracks[source]["output_sha256"],
                         "to_output_sha256": tracks[target]["output_sha256"], "recipe": recipe})
    return {"version": 1, "tracks": records, "handoffs": handoffs}


def main():
    approvals_path = ROOT / "priv/music/fixtures/approvals.json"
    with tempfile.TemporaryDirectory(prefix="music-fixture-") as directory:
        sources = Path(directory)
        tracks = {}
        for slug, (frequency, title, entry) in TONES.items():
            wav = sources / f"{slug}.wav"
            subprocess.run(["ffmpeg", "-hide_banner", "-nostats", "-y", "-f", "lavfi", "-i",
                            f"sine=frequency={frequency}:duration=40:sample_rate=48000", "-ac", "2",
                            "-fflags", "+bitexact", "-flags:a", "+bitexact", str(wav)],
                           check=True, capture_output=True)
            tracks[slug] = {"source": wav.name, "source_sha256": prepare_music.sha256(wav), "title": title,
                            "artists": ["Fixture Composer"], "credit": "Fixture Composer",
                            "source_url": f"https://example.test/{slug}", "licence": "CC BY 4.0",
                            "licence_url": "https://creativecommons.org/licenses/by/4.0/", "entry_s": entry}
        roster = {"recipe": RECIPE, "palettes": PALETTES, "tracks": tracks}
        manifest, _ = prepare_music.prepare(roster, sources, ROOT / "priv/audio/fixtures", approvals_path)
    approvals_path.parent.mkdir(parents=True, exist_ok=True)
    approvals_path.write_text(json.dumps(approve_all(manifest), indent=2) + "\n")


if __name__ == "__main__":
    main()
