#!/usr/bin/env python3
"""Prepare the soundtrack: verify, trim, gain-match and encode the roster.

Run by hand. Sources stay outside the repository (by default the retained audit
directory), so CI cannot regenerate the audio; tests check the committed
outputs and their approvals instead. This script never writes listening
approvals. It reads them only to report which ones its new outputs would make
stale, so re-encoding one track cannot erase another track's sign-off.
"""
import argparse
import hashlib
import json
import math
import re
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SILENCE = re.compile(r"silence_(start|end): (-?[\d.]+)")


def sha256(path):
    digest = hashlib.sha256()
    with open(path, "rb") as file:
        for chunk in iter(lambda: file.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def silence_bounds(log, duration):
    """Leading and trailing boundary silence from ffmpeg silencedetect output."""
    intervals, start = [], None
    for kind, value in SILENCE.findall(log):
        if kind == "start":
            start = float(value)
        elif start is not None:
            intervals.append((start, float(value)))
            start = None
    if start is not None:
        intervals.append((start, duration))
    lead = intervals[0][1] if intervals and intervals[0][0] <= 0.001 else 0.0
    tail = intervals[-1][0] if intervals and intervals[-1][1] >= duration - 0.01 else duration
    if tail <= lead:
        raise ValueError("recording is silent throughout")
    return round(lead, 3), round(tail, 3)


def loudness(log):
    integrated = re.findall(r"I:\s+(-?[\d.]+) LUFS", log)
    peak = re.findall(r"Peak:\s+(-?[\d.]+|-inf) dBFS", log)
    if not integrated or not peak:
        raise ValueError("ebur128 summary missing")
    return float(integrated[-1]), float(peak[-1])


def gain_db(integrated, true_peak, target, ceiling):
    return round(min(target - integrated, ceiling - true_peak), 2)


def encoded_entry(entry_source, lead, duration):
    entry = round(max(0.0, entry_source - lead), 3)
    if entry >= duration:
        raise ValueError(f"entry {entry_source} s lies beyond the trimmed recording")
    return entry


def edits_text(lead, trailing, gain, recipe):
    trims = []
    if lead > 0:
        trims.append(f"{lead:.2f} s of leading silence")
    if trailing > 0:
        trims.append(f"{trailing:.2f} s of trailing silence")
    trimmed = "Trimmed " + " and ".join(trims) + "; " if trims else ""
    return f"{trimmed}gain {gain:+.2f} dB; encoded as Opus {recipe['bitrate_kbps']} kbps."


class Tools:
    def run(self, *args):
        return subprocess.run([str(arg) for arg in args], check=True, capture_output=True, text=True)

    def duration(self, path):
        out = self.run("ffprobe", "-v", "error", "-show_entries", "format=duration",
                       "-of", "default=nw=1:nk=1", path).stdout
        return float(out.strip())

    def silence_log(self, path, noise_db):
        return self.run("ffmpeg", "-hide_banner", "-nostats", "-i", path, "-map", "0:a:0",
                        "-af", f"silencedetect=noise={noise_db}dB:d=0.1", "-f", "null", "-").stderr

    def loudness_log(self, path, lead, tail):
        return self.run("ffmpeg", "-hide_banner", "-nostats", "-i", path, "-map", "0:a:0",
                        "-af", f"atrim=start={lead}:end={tail},ebur128=peak=true",
                        "-f", "null", "-").stderr

    def encode(self, path, lead, tail, gain, bitrate, out):
        self.run("ffmpeg", "-hide_banner", "-nostats", "-y", "-i", path, "-map", "0:a:0",
                 "-af", f"atrim=start={lead}:end={tail},asetpts=PTS-STARTPTS,volume={gain}dB",
                 "-map_metadata", "-1", "-fflags", "+bitexact", "-flags:a", "+bitexact",
                 "-ac", "2", "-ar", "48000", "-c:a", "libopus", "-b:a", f"{bitrate}k",
                 "-vbr", "on", out)


def encode_verified(tools, source, lead, tail, gain, recipe, output):
    """Verify the decoded encode, lowering one source gain without compression."""
    ceiling = recipe["true_peak_dbtp"]
    for _ in range(5):
        tools.encode(source, lead, tail, gain, recipe["bitrate_kbps"], output)
        duration = tools.duration(output)
        _, peak = loudness(tools.loudness_log(output, 0, duration))
        if not math.isfinite(peak):
            raise ValueError(f"{source.name}: encoded true peak is not finite")
        if peak <= ceiling:
            return gain, duration, peak
        # ebur128 reports tenths of a dB; leave another tenth of headroom.
        gain = round(gain + ceiling - peak - 0.1, 2)
    raise ValueError(f"{source.name}: encoded true peak exceeds {ceiling} dBTP after five attempts")


def stale_approvals(manifest, approvals):
    """Approved decisions whose bound files or recipe no longer match."""
    tracks, recipe, stale = manifest["tracks"], manifest["recipe"], []

    def bound(entry, binding):
        return all(entry.get(key) == value for key, value in binding.items())

    for slug, parts in approvals.get("tracks", {}).items():
        track = tracks.get(slug)
        for part, entry in parts.items():
            if entry.get("decision") != "approved":
                continue
            if track is None:
                binding = None
            elif part == "recording":
                binding = {"source_sha256": track["source_sha256"]}
            else:
                binding = {"output_sha256": track["output_sha256"], "entry_s": track["entry_s"], "recipe": recipe}
            if binding is None or not bound(entry, binding):
                stale.append(f"{slug} {part}")
    for handoff in approvals.get("handoffs", []):
        if handoff.get("decision") != "approved":
            continue
        source, target = tracks.get(handoff.get("from")), tracks.get(handoff.get("to"))
        binding = None
        if source and target:
            binding = {"from_output_sha256": source["output_sha256"],
                       "to_output_sha256": target["output_sha256"], "recipe": recipe}
            if handoff.get("kind") == "port-to-voyage":
                binding["to_entry_s"] = target["entry_s"]
        if binding is None or not bound(handoff, binding):
            stale.append(f"{handoff.get('from')} → {handoff.get('to')} {handoff.get('kind')}")
    return stale


def validate_pools(manifest):
    for palette in manifest["palettes"]:
        for role in ("port", "voyage"):
            if not palette[role]:
                raise ValueError(f"{palette['id']} has no {role} track")
            for slug in palette[role]:
                if slug not in manifest["tracks"]:
                    raise ValueError(f"{palette['id']} {role} pool names {slug}, which is not in the roster")


def prepare(roster, sources, out_dir, approvals_path, tools=None, log=print):
    tools = tools or Tools()
    recipe = roster["recipe"]
    out_dir.mkdir(parents=True, exist_ok=True)
    tracks = {}
    for slug, entry in roster["tracks"].items():
        source = sources / entry["source"]
        actual = sha256(source)
        if actual != entry["source_sha256"]:
            raise SystemExit(f"{slug}: source hash {actual} does not match the roster")
        duration = tools.duration(source)
        lead, tail = silence_bounds(tools.silence_log(source, recipe["silence_floor_db"]), duration)
        integrated, peak = loudness(tools.loudness_log(source, lead, tail))
        gain = gain_db(integrated, peak, recipe["loudness_lufs"], recipe["true_peak_dbtp"])
        output = out_dir / f"{slug}.ogg"
        gain, encoded, encoded_peak = encode_verified(tools, source, lead, tail, gain, recipe, output)
        encoded = round(encoded, 3)
        notices = []
        for notice in entry.get("notices", []):
            notice_source = sources / notice["source"]
            if sha256(notice_source) != notice["sha256"]:
                raise SystemExit(f"{slug}: notice {notice['source']} does not match the roster")
            target = out_dir / "notices" / notice["file"]
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(notice_source, target)
            notices.append({"name": notice["name"], "file": f"notices/{notice['file']}"})
        entry_source = entry.get("entry_s", 0)
        tracks[slug] = {
            "file": output.name,
            "title": entry["title"],
            "artists": entry["artists"],
            "credit": entry["credit"],
            "source_url": entry["source_url"],
            "licence": entry["licence"],
            "licence_url": entry["licence_url"],
            "source_sha256": actual,
            "output_sha256": sha256(output),
            "duration_s": encoded,
            "trim_start_s": lead,
            "trim_end_s": round(duration - tail, 3),
            "gain_db": gain,
            "true_peak_dbtp": encoded_peak,
            "entry_source_s": entry_source,
            "entry_s": encoded_entry(entry_source, lead, encoded),
            "notices": notices,
            "edits": edits_text(lead, duration - tail, gain, recipe),
        }
        log(f"prepared {slug}: gain {gain:+.2f} dB, {encoded:.3f} s")
    manifest = {"version": 1, "recipe": recipe, "palettes": roster["palettes"], "tracks": tracks}
    validate_pools(manifest)
    (out_dir / "music.json").write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n")
    approvals = json.loads(approvals_path.read_text()) if approvals_path.exists() else {}
    stale = stale_approvals(manifest, approvals)
    for item in stale:
        log(f"approval made stale: {item}")
    return manifest, stale


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--roster", type=Path, default=ROOT / "scripts/music-roster.json")
    parser.add_argument("--sources", type=Path, default=ROOT / "tmp/music-audit-2026-10-10")
    parser.add_argument("--out", type=Path, default=ROOT / "priv/audio")
    parser.add_argument("--approvals", type=Path, default=ROOT / "priv/music/approvals.json")
    args = parser.parse_args()
    roster = json.loads(args.roster.read_text())
    _, stale = prepare(roster, args.sources, args.out, args.approvals)
    if stale:
        print(f"{len(stale)} approval(s) are now stale; record new listening decisions before release.")


if __name__ == "__main__":
    main()
