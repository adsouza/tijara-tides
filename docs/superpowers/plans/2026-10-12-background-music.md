# Background Music Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Play regional port and voyage music that follows the player's latest
explicit ship or port selection, with DESIGN.md's transition timing, a
device-persisted toggle and volume, credits, and a release listening gate that
keeps production playback off until every recording and handoff is approved.

**Architecture:** The server only records the player's explicit focus
(`music_focus`) and renders the resulting musical context as data attributes;
it also decides whether music is available (enable flag, real audio files,
hash-bound approvals). A committed manifest maps ports to twelve palettes and
describes 28 gain-matched Ogg Opus recordings stored in Git LFS. In the
browser, a pure policy module chooses pieces, a director state machine owns
every fade and timer, and an engine streams `<audio>` elements through Web
Audio gain nodes.

**Tech Stack:** Elixir/Phoenix LiveView, HEEx, Gettext (English/Arabic), plain
ES modules bundled by esbuild, Web Audio API, `node --test`, Playwright
Chromium, Python 3 with ffmpeg/ffprobe for preparation, Git LFS.

**Spec:** [docs/superpowers/specs/2026-10-12-background-music-design.md](../specs/2026-10-12-background-music-design.md)

## Deviation from the spec, recorded in Task 1

The spec places audio under `priv/static/audio/` and adds `audio` to
`static_paths`. `mix phx.digest` copies every file under `priv/static` to a
fingerprinted twin, which would ship each recording twice in the release (about
37 MB extra). This plan serves the soundtrack from `priv/audio/` through a
dedicated `Plug.Static` mounted at `/audio`. URLs, range support, LFS tracking
and every other contract are unchanged. Task 1 amends the spec so the two
documents agree.

## Global Constraints

- Selection transition: 3 s settle, 5 s outgoing fade with gain
  `from * cos(pi * p / 2)`, 2 s incoming fade with gain
  `from + (1 - from) * sin(pi * p / 2)`, 1 s silence after a completed fade
  before a superseding piece, 3 s silent wait restarted by each change while
  silent. All timers use real elapsed time.
- Between pieces: prepare 10 s before the end; 2 s crossfade beginning 2 s
  before the end, same curves.
- Turning music off and switching away fade out over 1 s.
- Volume slider 0–100, default 30, gain `(v / 100) ** 2`, 50 ms ramp.
- `localStorage` keys `tijara.music.enabled` and `tijara.music.volume`.
- Credit strip shows for 8 s, text from gettext template
  `"Now playing: %{title} by %{artists}"`.
- Load and seek timeout 10 s from preparation; playback timeout 10 s from the
  `play()` call; three consecutive failures stop music until the next identity
  change.
- Selection entries in original source seconds: Setting Sail 8, Imperial China
  Cinematic 16, Epic Indian Orchestral Fusion 8, Conquer The Great Sands 30,
  Cinematic Latin Music 2, Pathfinder 1; all others 0.
- Preparation: trim boundary audio below -60 dBFS, one linear gain toward -20
  LUFS capped so the decoded Opus output's measured true peak ≤ -1 dBTP,
  stereo Ogg Opus 64 kbps at 48 kHz, bit-exact muxing. Verify after encoding;
  reduce the constant source gain and re-encode if the codec raises the peak.
- Audio and notices live in `priv/audio/` and are tracked by Git LFS
  (`priv/audio/*.ogg`, `priv/audio/notices/*.pdf`); fixtures in
  `priv/audio/fixtures/` are ordinary files.
- Approvals live only in `priv/music/approvals.json`; preparation never writes
  it. The release gate requires a reviewed cross-region voyage pair in both
  directions. Repeats, port tracks and unknown tracks cannot satisfy that check.
- Production playback flag `TIJARA_MUSIC_ENABLED` defaults to false.
- Controls carry no `name` attribute (FormFields rejects named controls
  outside submit forms).
- Every new message has an Arabic translation; run `mix gettext.extract`,
  never `mix gettext.merge`.
- Compile and test output contain zero warnings; count them.
- Markdown prose is hard-wrapped near 80 columns; edit whole paragraphs.
- Commit on `main`; no branches. Commit messages end with
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Before each code commit run `mix precommit` and
  `python3 scripts/test-game-db.py` (AGENTS.md). Tasks touching JavaScript
  also run `npm run desktop:test`.
- After adding a guard or test, break the behavior once and confirm a test
  fails, then restore it.

## Review Focus

1. **The game opens unfocused or in a background tab.** Music must not start
   until the window is both visible and focused, then start normally. Test:
   Task 11, "waits for foreground before starting".
2. **The server names a port the manifest does not know** (a port added to
   the catalogue before the soundtrack). Music should fade out like any context
   change and stay silent, without throwing. Tests: Task 9 policy
   "unknown ports have no identity", Task 11 "an unknown port fades to
   silence", and Task 5's manifest test catches catalogue drift.
3. **Rapid on/off toggling inside the one-second fade.** Exactly one new piece
   may play and the old element must still be disposed. Test: Task 11,
   "toggling back on during the off-fade starts one fresh piece".
4. **Manifest fetch fails or returns malformed JSON.** Controls hide and no
   exception escapes the hook. Test: Task 12, "hides controls when the
   manifest cannot load".
5. **Voyage progress changes on every refresh.** The same palette pair must
   not restart or fade anything. Test: Task 11, "progress updates within a
   voyage change nothing".
6. **The three-failure limit is reached during automatic preparation.** Stop
   audible music and further attempts; toggle, foreground and same-identity
   updates cannot release the lock. Task 11 covers initial and automatic
   failures and recovery after an identity change while disabled or away.
7. **Switching away during an overlap.** Retain the current port voice and
   its position, while disposing the older outgoing voice. Task 11 covers
   both automatic and selection overlaps.
8. **Opus encoding raises a recording's true peak.** Task 2 checks the
   decoded encode and adjusts the source gain; Task 3 independently measures
   the final outputs. Source-only peak measurements are insufficient.
9. **A repeat is submitted as a cross-region audition.** Task 5 rejects
   same-palette, port and unknown-track handoffs and requires a reverse for
   every recorded cross-region voyage pair.

---

### Task 1: Git LFS tooling, hooks and spec amendment

**Files:**
- Create: `.gitattributes`
- Create: `.githooks/post-checkout`, `.githooks/post-commit`, `.githooks/post-merge`
- Modify: `.githooks/pre-push`
- Modify: `docs/deploying.md`
- Modify: `docs/superpowers/specs/2026-10-12-background-music-design.md`

**Interfaces:**
- Produces: LFS tracking for `priv/audio/*.ogg` and
  `priv/audio/notices/*.pdf`; hooks that upload LFS objects on push.

- [ ] **Step 1: Install Git LFS (ask first)**

`git-lfs` is not installed. Ask the user before running:

```bash
brew install git-lfs
```

Then configure filters for this clone only, without letting LFS write hooks
(the repository keeps tracked hooks in `.githooks/`):

```bash
git lfs install --local --skip-repo
git config --get filter.lfs.clean
```

Expected: `git-lfs clean -- %f`.

- [ ] **Step 2: Track the audio paths**

Create `.gitattributes`:

```gitattributes
# Background music recordings and their supplied licence notices.
# Fixtures under priv/audio/fixtures/ are small ordinary files.
priv/audio/*.ogg filter=lfs diff=lfs merge=lfs -text
priv/audio/notices/*.pdf filter=lfs diff=lfs merge=lfs -text
```

Verify:

```bash
git check-attr filter priv/audio/shenyang.ogg priv/audio/notices/x.pdf priv/audio/fixtures/east-port.ogg
```

Expected: `lfs`, `lfs`, `unspecified`.

- [ ] **Step 3: Add the LFS hooks**

Create `.githooks/post-checkout`, `.githooks/post-commit` and
`.githooks/post-merge`, each with this content, replacing `post-checkout`
in the last line with the hook's own name:

```sh
#!/bin/sh
command -v git-lfs >/dev/null 2>&1 || { printf >&2 "\n%s\n\n" "This repository stores music in Git LFS, but 'git-lfs' was not found. Install it with: brew install git-lfs"; exit 2; }
git lfs post-checkout "$@"
```

```bash
chmod +x .githooks/post-checkout .githooks/post-commit .githooks/post-merge
```

- [ ] **Step 4: Chain LFS into pre-push**

Replace `.githooks/pre-push` with:

```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
input=$(cat)
head=$(git rev-parse HEAD)
check=false
bases=()
full=false
while read -r local_ref local_sha remote_ref remote_sha; do
  [[ -z "${local_ref:-}" ]] && continue
  [[ "$local_sha" =~ ^0+$ ]] && continue
  if [[ "$(git rev-parse "$local_sha^{commit}")" != "$head" ]]; then
    echo "Pre-push: check out the commit being pushed ($local_ref) so its checks can run." >&2
    exit 1
  fi
  check=true
  bases+=(--base "$remote_sha")
  [[ "$remote_ref" == refs/heads/* ]] || full=true
done <<< "$input"
if "$check"; then
  if [[ -n "$(git status --porcelain --untracked-files=normal)" ]]; then
    echo "Pre-push: commit or stash changes first so validation tests exactly the commit being pushed." >&2
    exit 1
  fi
  if "$full"; then
    scripts/check-local.sh --full
  else
    scripts/check-local.sh "${bases[@]}"
  fi
fi
# Upload LFS objects only after validation passes.
command -v git-lfs >/dev/null 2>&1 || { echo "Pre-push: install Git LFS (brew install git-lfs) before pushing music." >&2; exit 2; }
printf '%s\n' "$input" | git lfs pre-push "$@"
```

- [ ] **Step 5: Run the hook and validation-scope tests**

```bash
python3 scripts/test-validation-scope.py
python3 scripts/test-server-validation.py
```

Expected: both pass. If either asserts on the old hook text (for example on
`exec scripts/check-local.sh`), update that assertion to the new structure and
rerun; the behavior it protects (checks run for the pushed commit, full
validation for non-branch refs) is unchanged.

- [ ] **Step 6: Amend the spec's paths**

In the spec, replace `priv/static/audio/` with `priv/audio/` everywhere, and
replace the whole **Serving** paragraph with:

```markdown
A dedicated `Plug.Static` mounted at `/audio` serves `priv/audio/`.
Keeping the soundtrack out of `priv/static` stops `phx.digest` from shipping a
fingerprinted second copy of every recording, and `.ogg` is not compressed.
Plug.Static supports byte-range requests and partial responses, so the
`<audio>` element can request data for an entry offset or paused position.
Verify HTTP 206 and `Content-Range` through the deployed serving path, as well
as ordinary full-file playback. A seek is asynchronous even with range support;
it remains subject to the readiness gate.
```

Check the wrap: `awk 'length > 80 && !/^\|/' docs/superpowers/specs/2026-10-12-background-music-design.md`
prints nothing.

- [ ] **Step 7: Document developer setup**

Add this section to `docs/deploying.md` immediately before
`## Current limitations`:

```markdown
## Background music files

The soundtrack's recordings and supplied licence notices are stored with Git
LFS (`priv/audio/*.ogg` and `priv/audio/notices/*.pdf`). Install Git LFS once
per machine (`brew install git-lfs`) and run `git lfs install --local
--skip-repo` in each clone; the tracked hooks in `.githooks/` already call LFS.
CI test jobs, the container smoke build and the desktop workflow check out
without LFS and see pointer files, which keep music unavailable but pass every
test. Production playback also requires `TIJARA_MUSIC_ENABLED=true` and
current listening approvals; see the background music design.
```

- [ ] **Step 8: Commit**

```bash
git add .gitattributes .githooks docs/deploying.md docs/superpowers/specs/2026-10-12-background-music-design.md
git commit -m "Track background music with Git LFS

Adds LFS attributes for the soundtrack and its notices, chains LFS into
the tracked hooks after validation, documents setup, and moves the
soundtrack to priv/audio so phx.digest does not duplicate it.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

`.gitattributes` and hooks are policy files, so the pre-commit and later
pre-push select full validation; that is expected.

---

### Task 2: Preparation script

**Files:**
- Create: `scripts/prepare-music.py`
- Create: `scripts/test-prepare-music.py`
- Modify: `scripts/check-server.sh`

**Interfaces:**
- Produces: `prepare(roster, sources, out_dir, approvals_path, tools=None, log=print) -> (manifest, stale)`;
  `stale_approvals(manifest, approvals) -> list[str]`; `sha256(path) -> str`.
  Manifest JSON shape (used by Tasks 3–12):

```json
{
  "version": 1,
  "recipe": {"strategy": "whole-recording", "settle_s": 3, "fade_out_s": 5,
             "fade_in_s": 2, "silence_s": 1, "crossfade_s": 2,
             "silence_floor_db": -60, "loudness_lufs": -20,
             "true_peak_dbtp": -1, "codec": "opus", "bitrate_kbps": 64},
  "palettes": [{"id": "chinese-coast", "name": "Chinese coast",
                "ports": ["Shanghai"], "port": ["shenyang"],
                "voyage": ["imperial-china-cinematic"]}],
  "tracks": {"shenyang": {"file": "shenyang.ogg", "title": "Shenyang",
             "artists": ["Kevin MacLeod"], "credit": "Kevin MacLeod (incompetech.com)",
             "source_url": "https://…", "licence": "CC BY 4.0",
             "licence_url": "https://…", "source_sha256": "…",
             "output_sha256": "…", "duration_s": 151.2, "trim_start_s": 0.0,
             "trim_end_s": 0.3, "gain_db": -6.78, "true_peak_dbtp": -7.1,
             "entry_source_s": 0,
             "entry_s": 0.0, "notices": [], "edits": "…"}}
}
```

- [ ] **Step 1: Write the failing tests**

Create `scripts/test-prepare-music.py`:

```python
#!/usr/bin/env python3
"""Unit tests for scripts/prepare-music.py with ffmpeg replaced by fakes."""
import hashlib
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("prepare_music", ROOT / "scripts/prepare-music.py")
prepare_music = importlib.util.module_from_spec(spec)
spec.loader.exec_module(prepare_music)

RECIPE = {"strategy": "whole-recording", "settle_s": 3, "fade_out_s": 5, "fade_in_s": 2,
          "silence_s": 1, "crossfade_s": 2, "silence_floor_db": -60, "loudness_lufs": -20,
          "true_peak_dbtp": -1, "codec": "opus", "bitrate_kbps": 64}


class FakeTools:
    """Ten-second sources with 0.5 s of silence at each end, -14 LUFS, -0.5 dBTP."""

    def __init__(self):
        self.encoded = []

    def duration(self, path):
        return 10.0 if path.suffix != ".ogg" else 9.0

    def silence_log(self, path, noise_db):
        return ("[silencedetect] silence_start: 0\n"
                "[silencedetect] silence_end: 0.5 | silence_duration: 0.5\n"
                "[silencedetect] silence_start: 9.5\n")

    def loudness_log(self, path, lead, tail):
        if path.suffix == ".ogg":
            gain = float(path.read_text().rsplit(" ", 1)[1])
            return f"I: {-14 + gain} LUFS\nPeak: {-0.5 + gain} dBFS\n"
        return "Summary:\n  Integrated loudness:\n    I:         -14.0 LUFS\n  True peak:\n    Peak:       -0.5 dBFS\n"

    def encode(self, path, lead, tail, gain, bitrate, out):
        self.encoded.append((path.name, lead, tail, gain, bitrate))
        out.write_bytes(f"OggS {path.name} {gain}".encode())


def digest(data):
    return hashlib.sha256(data).hexdigest()


class PrepareMusicTest(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.root = Path(self.dir.name)
        self.sources = self.root / "sources"
        self.sources.mkdir()
        (self.sources / "a.mp3").write_bytes(b"alpha")
        (self.sources / "b.mp3").write_bytes(b"bravo")
        (self.sources / "notice.pdf").write_bytes(b"notice")
        self.roster = {
            "recipe": RECIPE,
            "palettes": [{"id": "east", "name": "East", "ports": ["Busan"], "port": ["a"], "voyage": ["b"]}],
            "tracks": {
                "a": {"source": "a.mp3", "source_sha256": digest(b"alpha"), "title": "A", "artists": ["X"],
                      "credit": "X", "source_url": "https://example.test/a", "licence": "CC BY 4.0",
                      "licence_url": "https://creativecommons.org/licenses/by/4.0/"},
                "b": {"source": "b.mp3", "source_sha256": digest(b"bravo"), "title": "B", "artists": ["Y"],
                      "credit": "Y", "source_url": "https://example.test/b", "licence": "Pixabay Content License",
                      "licence_url": "https://pixabay.com/service/license-summary/", "entry_s": 8,
                      "notices": [{"name": "Release", "source": "notice.pdf", "sha256": digest(b"notice"),
                                   "file": "b-release.pdf"}]},
            },
        }
        self.out = self.root / "out"
        self.approvals = self.root / "approvals.json"

    def tearDown(self):
        self.dir.cleanup()

    def run_prepare(self, tools=None):
        return prepare_music.prepare(self.roster, self.sources, self.out, self.approvals,
                                     tools=tools or FakeTools(), log=lambda _line: None)

    def test_trims_gain_matches_and_translates_entries(self):
        tools = FakeTools()
        manifest, stale = self.run_prepare(tools)
        self.assertEqual(stale, [])
        b = manifest["tracks"]["b"]
        # -20 - (-14) = -6 dB; -1 - (-0.5) = -0.5 dB; the lower wins.
        self.assertEqual(b["gain_db"], -6.0)
        self.assertEqual(b["true_peak_dbtp"], -6.5)
        self.assertEqual((b["trim_start_s"], b["trim_end_s"]), (0.5, 0.5))
        self.assertEqual((b["entry_source_s"], b["entry_s"]), (8, 7.5))
        self.assertEqual(manifest["tracks"]["a"]["entry_s"], 0.0)
        self.assertEqual(tools.encoded[0], ("a.mp3", 0.5, 9.5, -6.0, 64))
        self.assertEqual(b["output_sha256"], digest((self.out / "b.ogg").read_bytes()))
        self.assertEqual(b["notices"], [{"name": "Release", "file": "notices/b-release.pdf"}])
        self.assertEqual((self.out / "notices/b-release.pdf").read_bytes(), b"notice")
        written = json.loads((self.out / "music.json").read_text())
        self.assertEqual(written, manifest)
        self.assertEqual(manifest["palettes"], self.roster["palettes"])

    def test_checks_codec_overshoot_and_reencodes_from_the_source(self):
        class OvershootTools(FakeTools):
            def loudness_log(self, path, lead, tail):
                if path.suffix == ".ogg":
                    gain = float(path.read_text().rsplit(" ", 1)[1])
                    return f"I: {-14 + gain} LUFS\nPeak: {-0.6 + gain + 6} dBFS\n"
                return super().loudness_log(path, lead, tail)

        tools = OvershootTools()
        manifest, _ = self.run_prepare(tools)
        for track in manifest["tracks"].values():
            self.assertEqual(track["gain_db"], -6.5)
            self.assertLessEqual(track["true_peak_dbtp"], RECIPE["true_peak_dbtp"])
            self.assertIn("gain -6.50 dB", track["edits"])
            self.assertEqual(track["output_sha256"], digest((self.out / track["file"]).read_bytes()))
        self.assertEqual(len(tools.encoded), 4)
        self.assertEqual([row[0] for row in tools.encoded], ["a.mp3", "a.mp3", "b.mp3", "b.mp3"])

    def test_rejects_an_encode_that_cannot_meet_the_peak_ceiling(self):
        class UnboundedTools(FakeTools):
            def loudness_log(self, path, lead, tail):
                if path.suffix == ".ogg":
                    return "I: -20 LUFS\nPeak: -0.6 dBFS\n"
                return super().loudness_log(path, lead, tail)

        tools = UnboundedTools()
        with self.assertRaisesRegex(ValueError, "encoded true peak"):
            self.run_prepare(tools)
        self.assertEqual(len(tools.encoded), 5)
        self.assertFalse((self.out / "music.json").exists())

    def test_never_writes_approvals_and_reports_stale_ones(self):
        manifest, _ = self.run_prepare()
        old = manifest["tracks"]["a"]
        approvals = {"version": 1, "tracks": {"a": {
            "recording": {"decision": "approved", "source_sha256": old["source_sha256"]},
            "playback": {"decision": "approved", "output_sha256": "0" * 64, "entry_s": 0.0,
                         "recipe": RECIPE}}},
            "handoffs": [{"kind": "port-to-voyage", "from": "a", "to": "b", "decision": "approved",
                          "from_output_sha256": old["output_sha256"],
                          "to_output_sha256": manifest["tracks"]["b"]["output_sha256"],
                          "to_entry_s": 7.5, "recipe": RECIPE}]}
        text = json.dumps(approvals, indent=2) + "\n"
        self.approvals.write_text(text)
        _, stale = self.run_prepare()
        self.assertEqual(stale, ["a playback"])
        self.assertEqual(self.approvals.read_text(), text)

    def test_rejects_a_changed_source(self):
        (self.sources / "a.mp3").write_bytes(b"changed")
        with self.assertRaisesRegex(SystemExit, "a: source hash"):
            self.run_prepare()

    def test_rejects_an_entry_beyond_the_trimmed_recording(self):
        self.roster["tracks"]["b"]["entry_s"] = 30
        with self.assertRaisesRegex(ValueError, "beyond the trimmed recording"):
            self.run_prepare()

    def test_rejects_a_pool_naming_an_unknown_track(self):
        self.roster["palettes"][0]["voyage"] = ["missing"]
        with self.assertRaisesRegex(ValueError, "missing"):
            self.run_prepare()

    def test_silence_bounds_and_loudness_parsing(self):
        lead, tail = prepare_music.silence_bounds("silence_start: 0\nsilence_end: 1.25 | x\n", 60.0)
        self.assertEqual((lead, tail), (1.25, 60.0))
        lead, tail = prepare_music.silence_bounds("silence_start: 58\nsilence_end: 60 | x\n", 60.0)
        self.assertEqual((lead, tail), (0.0, 58.0))
        with self.assertRaisesRegex(ValueError, "silent throughout"):
            prepare_music.silence_bounds("silence_start: 0\n", 60.0)
        self.assertEqual(prepare_music.loudness("I: -9.5 LUFS\nPeak: 0.4 dBFS\nI: -10.0 LUFS\nPeak: 0.2 dBFS\n"), (-10.0, 0.2))


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run it to verify it fails**

Run: `python3 scripts/test-prepare-music.py`
Expected: error loading `scripts/prepare-music.py` (file not found).

- [ ] **Step 3: Write the script**

Create `scripts/prepare-music.py` (mode 755):

```python
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
```

`encode_verified` measures the decoded output after each encode, not just the
source before encoding. On overshoot it lowers the one constant gain and
encodes again from the original source, overwriting the same output file; it
never transcodes a prior lossy encode or keeps duplicate audio. Five failed
attempts abort before publishing a new manifest. The manifest and edit notes
record the final gain, verified peak and final output hash.

Note `validate_pools` runs after encoding, so the pool test raises
`ValueError` naming `missing`; the test only checks the message.

- [ ] **Step 4: Run the tests**

Run: `python3 scripts/test-prepare-music.py`
Expected: `OK` (8 tests).

- [ ] **Step 5: Break it once**

Change `min(` to `max(` in `gain_db`; rerun; expect
`test_trims_gain_matches_and_translates_entries` to fail. Restore. Then make
`prepare` write `approvals_path.write_text("{}")` before returning; expect
`test_never_writes_approvals_and_reports_stale_ones` to fail. Restore.
Then return the first encode without checking its peak in `encode_verified`;
both encoded-peak tests must fail. Restore.

- [ ] **Step 6: Run it in CI**

In `scripts/check-server.sh`, add after `python3 scripts/test-format-staged.py`:

```bash
python3 scripts/test-prepare-music.py
```

- [ ] **Step 7: Commit**

```bash
chmod +x scripts/prepare-music.py scripts/test-prepare-music.py
git add scripts/prepare-music.py scripts/test-prepare-music.py scripts/check-server.sh
git commit -m "Add soundtrack preparation script

Verifies source hashes, trims boundary silence, applies one gain toward
-20 LUFS under a -1 dBTP ceiling, encodes bit-exact Opus and writes the
manifest. It reads approvals only to report stale ones.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Production roster, encoded soundtrack and credits document

**Files:**
- Create: `scripts/music-roster.json`
- Create: `priv/audio/*.ogg` (28, LFS), `priv/audio/notices/*.pdf` (2, LFS), `priv/audio/music.json`
- Create: `priv/music/approvals.json`
- Create: `scripts/gen-music-credits.py`, `docs/music-credits.md`
- Modify: `scripts/check-generated.py`

**Interfaces:**
- Consumes: `prepare-music.py` from Task 2.
- Produces: production manifest at `priv/audio/music.json`; approvals file
  `{"version": 1, "tracks": {}, "handoffs": []}`.

- [ ] **Step 1: Write the roster**

Create `scripts/music-roster.json`. `recipe` is the Task 2 recipe with
`"bitrate_kbps": 64`. Palettes, in this order, with ports exactly as in
DESIGN.md's palette table:

| id | name | ports | port | voyage |
|---|---|---|---|---|
| chinese-coast | Chinese coast | Shanghai, Shenzhen, Guangzhou, Hong Kong | shenyang | imperial-china-cinematic |
| japanese | Japanese | Tokyo | sakuya3 | ametsuchi |
| korean | Korean | Busan | listening-to-our-sounds | beautiful-korea, korean-gayageum |
| southeast-asian | Southeast Asian | Singapore, Ho Chi Minh City, Jakarta, Manila | hoi-an-ancient-charm | epic-nusantara |
| south-asian | South Asian | Mumbai, Colombo | dhaka | epic-indian-orchestral-fusion |
| arabian-gulf | Arabian Gulf | Dubai, Abu Dhabi | middle-east-ballad | conquer-the-great-sands |
| north-african | North African | Tangier | arabic-music, desert2 | folk-arabian |
| mediterranean | Mediterranean | Valencia, Athens | dellasera | atlas-greece, cinematic-latin-music |
| northern-frangistan | Northern Frangistan | Rotterdam, Antwerp, Hamburg | lord-of-the-land | pathfinder |
| north-american | North American | Los Angeles, New York City, Houston | swing-train, market-on-the-sea | the-world-at-your-door |
| caribbean | Caribbean | Colón | beachfront-celebration | setting-sail |
| brazilian | Brazilian | São Paulo | sideways-samba | up-in-the-air |

Tracks (`source` is relative to `tmp/music-audit-2026-10-10/`). Licence
columns: CC4 = `"CC BY 4.0"`, `https://creativecommons.org/licenses/by/4.0/`;
CC3 = `"CC BY 3.0"`, `https://creativecommons.org/licenses/by/3.0/`; PB =
`"Pixabay Content License"`, `https://pixabay.com/service/license-summary/`;
DC = `"Darren Curtis Materials Release"`, `https://www.darrencurtismusic.com/world-music`.

| slug | source | source_sha256 | title | artists | credit | source_url | licence | entry_s |
|---|---|---|---|---|---|---|---|---|
| shenyang | shenyang-mp3.mp3 | 1cf2e0f57f820d82e9066ba4dca076735aedd512bc1909fdaa2e0065bd866786 | Shenyang | Kevin MacLeod | Kevin MacLeod (incompetech.com) | https://www.incompetech.com/music/royalty-free/index.html?isrc=USUAN1600066 | CC4 | 0 |
| imperial-china-cinematic | imperial-china-mp3.mp3 | 4a8bf29f72af49ad3e031f2c4f6c4bc05af2b2fadc2013dccb4dbaa4e800bc54 | Imperial China Cinematic | Shane Ivers | Shane Ivers / silvermansound.com | https://www.silvermansound.com/free-music/imperial-china-cinematic | CC4 | 16 |
| sakuya3 | sakuya3-mp3.mp3 | 21ff78d194af9557d299fee64730b8726d3a440e583a70b979bc7f6a6df254cf | Sakuya3 | PeriTune | PeriTune / Sei Mutsuki (むつき醒) | https://peritune.com/blog/2016/10/18/sakuya3/ | CC4 | 0 |
| ametsuchi | ametsuchi-mp3.mp3 | c17eb0bf7dc6b23417d05628b26221ec51f66d1b35b25cb41d88363cfded3c3e | Ametsuchi | PeriTune | PeriTune / Sei Mutsuki (むつき醒) | https://peritune.com/blog/2018/10/01/ametsuchi/ | CC4 | 0 |
| listening-to-our-sounds | im-dasol-our-sounds-mp3.mp3 | b911952759ef2e1257e622d165a2efe2993c64a5e17a33e506469f2d5ade07ff | 우리네 소리를 듣다 (Listening to Our Sounds) | 임다솔 (Im Dasol) | 임다솔 (Im Dasol) / GongU Madang | https://gongu.copyright.or.kr/gongu/wrt/wrt/view.do?menuNo=200020&wrtSn=13048780 | CC4 | 0 |
| beautiful-korea | beautiful-korea-original.wav | 9cf1764e974607463713c024151e6372759bbf6f05a928d737cdb9321474e215 | Beautiful Korea (뷰티플 코리아) | 윤영현 | 윤영현 / GongU Madang | https://gongu.copyright.or.kr/gongu/wrt/wrt/view.do?menuNo=200020&wrtSn=13048827 | CC4 | 0 |
| korean-gayageum | korean-gayageum-mp3.mp3 | 07eabbeefd563b41613a2ef7f8a932f2c8e8ced7553a34c660112178e92e7de0 | Korean traditional-cinematic piece with gayageum | RibhavAgrawal | RibhavAgrawal (Pixabay) | https://pixabay.com/music/orchestral-korean-traditional-cinematic-piece-with-gayageum-589500/ | PB | 0 |
| hoi-an-ancient-charm | hoi-an-mp3.mp3 | 4ccc84353258f828ba25fdabb1c94f37e9279754d02f0470c128f56a7e5632c8 | Hoi An Ancient Charm | VPRODMUSIC_Asia_BGM | VPRODMUSIC_Asia_BGM (Pixabay) | https://pixabay.com/music/world-hoi-an-ancient-charm-147064/ | PB | 0 |
| epic-nusantara | epic-nusantara-mp3.mp3 | 84b32f1ecc6cdfafe9bed28e67260d93fd67f65a5c4c293caf35c84940130943 | Epic Nusantara - Free Gamelan Music from Indonesian | fiikuri | fiikuri (Pixabay) | https://pixabay.com/music/world-epic-nusantara-free-gamelan-music-from-indonesian-328513/ | PB | 0 |
| dhaka | dhaka-mp3.mp3 | 2196a22f4a96de9c03e3d6c1589ac5b3234641caa7f1afd2299b0e418ab53ab0 | Dhaka | Kevin MacLeod | Kevin MacLeod (incompetech.com) | https://incompetech.com/music/royalty-free/index.html?isrc=USUAN1400003 | CC4 | 0 |
| epic-indian-orchestral-fusion | epic-indian-fusion-mp3.mp3 | 1d5f8d754964439415180f39cbcbee52963168063e922bd6af23bd78c6bffc18 | Epic Indian Orchestral Fusion | Alejandro Piñero Amerio (vjgalaxy) | Alejandro Piñero Amerio (vjgalaxy) (Pixabay) | https://pixabay.com/music/india-epic-indian-orchestral-fusion-570933/ | PB | 8 |
| middle-east-ballad | middle-east-ballad-mp3.mp3 | d59dd1ae0e41bb069683e644bbe34b09d9c8a4e74a35536f336a46496645e5c1 | Middle East Ballad | Abydos_Music | Abydos_Music (Pixabay) | https://pixabay.com/music/world-middle-east-ballad-188926/ | PB | 0 |
| conquer-the-great-sands | conquer-sands-files/Conquer the Great Sands OGG.ogg | f3ac8a49aa79aeb5e7f801194a023b498c3dcbe950c52947d48638942fe2c59b | Conquer The Great Sands | Darren Curtis | Darren Curtis / darrencurtismusic.com | https://www.darrencurtismusic.com/world-music | DC | 30 |
| arabic-music | kiravale-arabic-mp3.mp3 | d6f50a99dcae46e2d9b6df15052effdca4bc8eb123b9da965223dbae40a856f1 | Arabic Music | kiravale | kiravale (Pixabay) | https://pixabay.com/music/arabic-arabic-music-593673/ | PB | 0 |
| desert2 | peritune-desert2-mp3.mp3 | 591d1e5bc6de1f4c2b9b48299f6048d2d3baba87cf6ff5d42530f707e563465f | Desert2 | PeriTune | PeriTune / Sei Mutsuki (むつき醒) | https://peritune.com/blog/2018/05/01/desert2/ | CC4 | 0 |
| folk-arabian | folk-arabian-mp3.mp3 | 958c97661057ac0bed77df638f94d1c2e6fdd95be84695b028eba860c61e0d83 | Folk_Arabian | PeriTune | PeriTune / Sei Mutsuki (むつき醒) | https://peritune.com/blog/2016/11/28/folk_arabian/ | CC4 | 0 |
| dellasera | dellasera-mp3.mp3 | ad7fd4e2801e4639e036c6c8e853590a343c843ab4999c2cb84157f2b4a32bd3 | Dellasera | Shane Ivers | Shane Ivers / silvermansound.com | https://www.silvermansound.com/free-music/dellasera | CC4 | 0 |
| atlas-greece | atlas-greece-mp3.mp3 | 3ea6cf484d3a50da687356147ae17c3dc6baee038ec26e808df86595052987fb | Atlas • Greece | Vadim_Makes_Sound | Vadim_Makes_Sound (Pixabay) | https://pixabay.com/music/orchestral-atlas-greece-555434/ | PB | 0 |
| cinematic-latin-music | cinematic-latin-mp3.mp3 | f247da8604b430656d6a5b6195601b90146ed40dac4f03a8ea97556139c580e7 | Cinematic Latin Music | Sonican | Sonican (Pixabay) | https://pixabay.com/music/latin-cinematic-latin-music-523433/ | PB | 2 |
| lord-of-the-land | lord-mp3.mp3 | 47ce185fdc1f2e5514566307d652d6cb62a06bed47ea730e28214d3cedc2f948 | Lord of the Land | Kevin MacLeod | Kevin MacLeod (incompetech.com) | https://incompetech.com/music/royalty-free/index.html?Search=Search&isrc=USUAN1400022 | CC4 | 0 |
| pathfinder | pathfinder-mp3.mp3 | f20e3e9aaac2d947510ec971d7ea477320370091c3ea7b1541792c3fe5683e78 | Pathfinder | Scott Buckley | Scott Buckley / scottbuckley.com.au | https://www.scottbuckley.com.au/library/pathfinder/ | CC4 | 1 |
| swing-train | swing-train-mp3.mp3 | b66669c82cd86ca93f0ceb2556c7c4fa5713dd592b81a6ac2f97870e2877048b | Swing Train - Big Band Miller Style | JuliusH | JuliusH (Pixabay) | https://pixabay.com/music/big-band-swing-train-big-band-miller-style-2667/ | PB | 0 |
| market-on-the-sea | market-sea-legacy/Market on the Sea - MP3.mp3 | 8c7b6db9dd571cb1ec6eea6c7b035f2c0541c37d95d10f868bc38fe87eff6d8d | Market on the Sea | Jonathan Shaw | Jonathan Shaw / jshaw.co.uk | https://opengameart.org/content/market-on-the-sea-rpg-orchestral-essentials-village-music | CC3 | 0 |
| the-world-at-your-door | jshaw-world-legacy/The World At Your Door MP3.mp3 | e9de1adfaf385d003ae3e281bd1d7158e0d8c127964177daf8eea75a072eaa64 | The World At Your Door | Jonathan Shaw | Jonathan Shaw / jshaw.co.uk | https://opengameart.org/content/the-world-at-your-door-rpg-orchestral-essentials-overworld-music | CC3 | 0 |
| beachfront-celebration | beachfront-celebration-mp3.mp3 | 73ffcea8277780253b4e42dcbc3c5b3c50ba8ad343023372726a8678f43cc68e | Beachfront Celebration | Kevin MacLeod | Kevin MacLeod (incompetech.com) | https://incompetech.com/music/royalty-free/index.html?isrc=USUAN1200022 | CC4 | 0 |
| setting-sail | setting-sail-mp3.mp3 | e496000eaa81a0a8eaeb8ae7fe5c441cf6b3a8610678600069f8e50bf9231e9c | Setting Sail | Alexander Nakarada | Alexander Nakarada / creatorchords.com | https://creatorchords.com/music/setting-sail/ | CC4 | 8 |
| sideways-samba | sideways-samba-mp3.mp3 | 2ee432954197d30320b95a915d3c029e446130f5eb0490347c87bb535dc7e159 | Sideways Samba | Jason Shaw | Jason Shaw / audionautix.com | https://audionautix.com/free-music/jazz | CC4 | 0 |
| up-in-the-air | brazil-up-in-air-mp3.mp3 | ba9ad15d406ddba4f9aa7df0ef8e51631a82605a1992e947c7698611fddc951e | Up In The Air | DonnySombrero | DonnySombrero (Pixabay) | https://pixabay.com/music/samba-latin-up-in-the-air-499093/ | PB | 0 |

`artists` is a JSON array with the single name shown. Add notices:

- `conquer-the-great-sands`: `{"name": "Conquer the Great Sands Materials Release", "source": "conquer-sands-files/Conquer the Great Sands Materials Release.pdf", "sha256": "6daa2978433b5461564021acb89f12df37ffc126ac15a2f108ed25f7fc117c7a", "file": "conquer-the-great-sands-materials-release.pdf"}`
- `market-on-the-sea`: `{"name": "RPG Orchestral Essentials licence", "source": "market-sea-legacy/LICENSE - RPG Orchestral Essentials.pdf", "sha256": "10a7ac194bb5d0c63687468d366639e3540ec33b7ed7a393a9c98dcbae067d3a", "file": "rpg-orchestral-essentials-licence.pdf"}`
- `the-world-at-your-door`: the same notice object, with source `jshaw-world-legacy/LICENSE - RPG Orchestral Essentials.pdf` (same hash, same target file).

Validate it parses and covers 28 tracks and 25 ports:

```bash
python3 -c "import json;r=json.load(open('scripts/music-roster.json'));print(len(r['tracks']),sum(len(p['ports']) for p in r['palettes']))"
```

Expected: `28 25`.

- [ ] **Step 2: Encode**

```bash
python3 scripts/prepare-music.py
```

Expected: 28 `prepared …` lines and no stale approvals (none exist yet).
Confirm the encode is deterministic, so approvals can bind to output hashes:

```bash
shasum -a 256 priv/audio/*.ogg > "$TMPDIR/music-first.sha"
python3 scripts/prepare-music.py >/dev/null
shasum -a 256 priv/audio/*.ogg | diff "$TMPDIR/music-first.sha" - && echo deterministic
du -sh priv/audio
```

Expected: `deterministic` and about 37 MB. If any hash differs, stop: the Ogg
muxer is not bit-exact on this ffmpeg build, and approvals could never bind.

Confirm every manifest track's `true_peak_dbtp` is at or below the recipe's
ceiling, then independently decode and measure each final Ogg with ffmpeg
`ebur128=peak=true`. Include Lord of the Land: the initial +1.2 dB source gain
produced -0.6 dBTP after Opus encoding in the review probe, so source-only
measurement is insufficient. The adjusted final encode must measure at or
below -1 dBTP. Do not record listening approvals until these output checks
pass.

- [ ] **Step 3: Create the empty approvals record**

Create `priv/music/approvals.json`:

```json
{
  "version": 1,
  "tracks": {},
  "handoffs": []
}
```

- [ ] **Step 4: Credits generator**

Create `scripts/gen-music-credits.py` (mode 755):

```python
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
```

Run `python3 scripts/gen-music-credits.py`.

- [ ] **Step 5: Verify the generated document**

In `scripts/check-generated.py`, add `"gen-music-credits.py": "docs/music-credits.md",`
to `generators`, and after `(target / "priv/game").mkdir(parents=True)` add:

```python
    (target / "priv/audio").mkdir(parents=True)
    shutil.copyfile(root / "priv/audio/music.json", target / "priv/audio/music.json")
```

Run `python3 scripts/check-generated.py --docs-only`.
Expected: `Generated docs match.` Then edit one character in
`docs/music-credits.md`, rerun, expect
`docs/music-credits.md: regenerate with scripts/gen-music-credits.py`, and
regenerate.

- [ ] **Step 6: Commit through LFS**

```bash
git add scripts/music-roster.json priv/audio priv/music/approvals.json scripts/gen-music-credits.py docs/music-credits.md scripts/check-generated.py
git lfs ls-files | wc -l
```

Expected: `30` (28 recordings and 2 notices; the shared Shaw licence is one
file). Then:

```bash
git commit -m "Add the prepared 28-track soundtrack

Encodes the roster's full recordings to gain-matched Opus in Git LFS,
records the manifest and an empty approvals file, and generates the
music credits document.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Synthetic fixture soundtrack

**Files:**
- Create: `scripts/make-music-fixture.py`
- Create: `priv/audio/fixtures/{east-port,east-voyage,west-port,west-voyage}.ogg`, `priv/audio/fixtures/music.json`
- Create: `priv/music/fixtures/approvals.json`

**Interfaces:**
- Consumes: `prepare()` and `sha256()` from Task 2.
- Produces: fixture palettes `east` (ports Guangzhou, Shanghai, Shenzhen,
  Hong Kong, Jakarta, Singapore, Ho Chi Minh City, Manila) and `west` (ports
  Tangier, Valencia, Athens, Hamburg, Rotterdam); tracks `east-port`
  ("East Harbour Tone"), `east-voyage` ("East Passage Tone"), `west-port`
  ("West Harbour Tone"), `west-voyage` ("West Passage Tone", entry 2 s); all by
  `Fixture Composer`, source URL `https://example.test/<slug>`; fully approved
  fixture approvals.

- [ ] **Step 1: Write the generator**

Create `scripts/make-music-fixture.py` (mode 755):

```python
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
```

- [ ] **Step 2: Generate and inspect**

```bash
python3 scripts/make-music-fixture.py
ls -l priv/audio/fixtures
git check-attr filter priv/audio/fixtures/east-port.ogg
```

Expected: four `.ogg` files of roughly 30 KB and `music.json`;
`filter: unspecified` (not LFS).

- [ ] **Step 3: Commit**

```bash
git add scripts/make-music-fixture.py priv/audio/fixtures priv/music/fixtures
git commit -m "Add a synthetic fixture soundtrack for tests

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Availability gate, serving and manifest tests

**Files:**
- Create: `lib/tijara_tides_web/music.ex`
- Modify: `lib/tijara_tides_web.ex` (Boundary exports)
- Modify: `lib/tijara_tides/application.ex`
- Modify: `lib/tijara_tides_web/endpoint.ex`
- Modify: `config/config.exs`, `config/dev.exs`, `config/test.exs`, `config/runtime.exs`
- Create: `test/tijara_tides_web/music_test.exs`
- Create: `test/docs/music_manifest_test.exs`, `test/docs/music_approvals_test.exs`
- Modify: `docs/architecture.md`, `docs/music-recording-audit.md`

**Interfaces:**
- Consumes: manifests and approvals from Tasks 3–4.
- Produces:
  - `TijaraTidesWeb.Music.status() :: :available | {:unavailable, [String.t()]}` (cached per boot)
  - `TijaraTidesWeb.Music.evaluate(manifest, approvals, directory, enabled: boolean, audition: boolean)`
  - `TijaraTidesWeb.Music.approval_report(manifest, approvals) :: %{optional(:approved | :pending | :rejected | :stale) => [String.t()]}`
  - `TijaraTidesWeb.Music.manifest() :: {:ok, map} | {:error, String.t()}`
  - `TijaraTidesWeb.Music.manifest_url() :: String.t()`
  - `TijaraTidesWeb.Music.credits(manifest) :: [%{slug, palette, role, title, credit, source_url, licence, licence_url, edits, notices: [%{name, url}]}]`
  - `GET /audio/...` serves `priv/audio` with range support.

- [ ] **Step 1: Configuration**

`config/config.exs`, after the esbuild block:

```elixir
# Background music. Production playback stays off until the release listening
# gate passes; see docs/superpowers/specs/2026-10-12-background-music-design.md.
config :tijara_tides, :music,
  enabled: false,
  audition: false,
  url: "/audio/music.json",
  manifest: "audio/music.json",
  approvals: "music/approvals.json"
```

`config/dev.exs`, at the end:

```elixir
# Developers may audition unapproved music with TIJARA_MUSIC_AUDITION=true.
config :tijara_tides, :music_audition_allowed, true
```

`config/test.exs`, after the `:settled_check` line:

```elixir
# Tests play the approved synthetic fixture soundtrack.
config :tijara_tides, :music,
  enabled: true,
  url: "/audio/fixtures/music.json",
  manifest: "audio/fixtures/music.json",
  approvals: "music/fixtures/approvals.json"
```

`config/runtime.exs`, near the top after `import Config`:

```elixir
if config_env() != :test do
  config :tijara_tides, :music,
    enabled: System.get_env("TIJARA_MUSIC_ENABLED") == "true",
    audition: System.get_env("TIJARA_MUSIC_AUDITION") == "true"
end
```

- [ ] **Step 2: Write the failing unit tests**

Create `test/tijara_tides_web/music_test.exs`:

```elixir
defmodule TijaraTidesWeb.MusicTest do
  use ExUnit.Case, async: true
  alias TijaraTidesWeb.Music

  @recipe %{"strategy" => "whole-recording", "fade_in_s" => 2}

  defp manifest do
    %{
      "recipe" => @recipe,
      "palettes" => [
        %{"id" => "east", "ports" => ["Busan"], "port" => ["p"], "voyage" => ["v"]},
        %{"id" => "west", "ports" => ["Tangier"], "port" => ["q"], "voyage" => ["w"]}
      ],
      "tracks" => %{
        "p" => %{"file" => "p.ogg", "source_sha256" => "sp", "output_sha256" => "op", "entry_s" => 0.0},
        "v" => %{"file" => "v.ogg", "source_sha256" => "sv", "output_sha256" => "ov", "entry_s" => 7.5},
        "q" => %{"file" => "q.ogg", "source_sha256" => "sq", "output_sha256" => "oq", "entry_s" => 0.0},
        "w" => %{"file" => "w.ogg", "source_sha256" => "sw", "output_sha256" => "ow", "entry_s" => 0.0}
      }
    }
  end

  defp approved(extra), do: Map.merge(%{"decision" => "approved"}, extra)

  defp approvals do
    %{
      "tracks" => %{
        "p" => %{
          "recording" => approved(%{"source_sha256" => "sp"}),
          "playback" => approved(%{"output_sha256" => "op", "entry_s" => 0.0, "recipe" => @recipe})
        },
        "v" => %{
          "recording" => approved(%{"source_sha256" => "sv"}),
          "playback" => approved(%{"output_sha256" => "ov", "entry_s" => 7.5, "recipe" => @recipe})
        },
        "q" => %{
          "recording" => approved(%{"source_sha256" => "sq"}),
          "playback" => approved(%{"output_sha256" => "oq", "entry_s" => 0.0, "recipe" => @recipe})
        },
        "w" => %{
          "recording" => approved(%{"source_sha256" => "sw"}),
          "playback" => approved(%{"output_sha256" => "ow", "entry_s" => 0.0, "recipe" => @recipe})
        }
      },
      "handoffs" => [
        approved(%{"kind" => "port-to-voyage", "from" => "p", "to" => "v",
          "from_output_sha256" => "op", "to_output_sha256" => "ov", "to_entry_s" => 7.5,
          "recipe" => @recipe}),
        approved(%{"kind" => "port-to-voyage", "from" => "q", "to" => "w",
          "from_output_sha256" => "oq", "to_output_sha256" => "ow", "to_entry_s" => 0.0,
          "recipe" => @recipe}),
        approved(%{"kind" => "voyage-handoff", "from" => "v", "to" => "w",
          "from_output_sha256" => "ov", "to_output_sha256" => "ow", "recipe" => @recipe}),
        approved(%{"kind" => "voyage-handoff", "from" => "w", "to" => "v",
          "from_output_sha256" => "ow", "to_output_sha256" => "ov", "recipe" => @recipe})
      ]
    }
  end

  setup do
    directory = Path.join(System.tmp_dir!(), "music-#{System.unique_integer([:positive])}")
    File.mkdir_p!(directory)
    for slug <- ~w(p v q w),
        do: File.write!(Path.join(directory, slug <> ".ogg"), "OggS" <> :binary.copy(<<0>>, 32))
    on_exit(fn -> File.rm_rf!(directory) end)
    %{directory: directory}
  end

  test "current approvals, real audio and the flag make music available", %{directory: dir} do
    assert Music.evaluate(manifest(), approvals(), dir, enabled: true) == :available
    assert %{approved: approved} = Music.approval_report(manifest(), approvals())
    assert length(approved) == 12
  end

  test "the flag, a pointer file and a missing approval each keep music off", %{directory: dir} do
    assert {:unavailable, ["music is disabled"]} =
             Music.evaluate(manifest(), approvals(), dir, enabled: false)

    File.write!(Path.join(dir, "v.ogg"), "version https://git-lfs.github.com/spec/v1\noid sha256:ab\n")
    assert {:unavailable, [reason]} = Music.evaluate(manifest(), approvals(), dir, enabled: true)
    assert reason =~ "v.ogg is not Ogg audio"

    File.write!(Path.join(dir, "v.ogg"), "OggS")
    pending = update_in(approvals()["tracks"], &Map.delete(&1, "v"))
    assert {:unavailable, reasons} = Music.evaluate(manifest(), pending, dir, enabled: true)
    assert "v recording pending" in reasons and "v playback pending" in reasons
  end

  test "each binding goes stale when what it was made against changes" do
    changed = put_in(manifest()["tracks"]["v"]["output_sha256"], "new")
    report = Music.approval_report(changed, approvals())
    assert "v playback" in report.stale
    assert "p → v handoff" in report.stale
    assert "v → w voyage handoff" in report.stale
    assert "w → v voyage handoff" in report.stale
    refute "v recording" in report.stale

    resourced = put_in(manifest()["tracks"]["p"]["source_sha256"], "new")
    assert Music.approval_report(resourced, approvals()).stale == ["p recording"]

    reentered = put_in(manifest()["tracks"]["v"]["entry_s"], 8.0)
    assert Enum.sort(Music.approval_report(reentered, approvals()).stale) ==
             ["p → v handoff", "v playback"]

    recipe = put_in(manifest()["recipe"]["fade_in_s"], 3)
    assert length(Music.approval_report(recipe, approvals()).stale) == 8
  end

  test "rejections, unknown tracks and a missing cross-region check are reported" do
    rejected = put_in(approvals()["tracks"]["p"]["recording"]["decision"], "rejected")
    assert Music.approval_report(manifest(), rejected).rejected == ["p recording"]

    unknown = put_in(approvals()["tracks"]["ghost"], %{})
    assert "ghost approvals for an unknown track" in Music.approval_report(manifest(), unknown).stale

    no_voyage = update_in(approvals()["handoffs"], &Enum.reject(&1, fn h -> h["kind"] == "voyage-handoff" end))
    assert Music.approval_report(manifest(), no_voyage).pending == ["cross-region voyage handoff"]
  end

  test "audition skips approvals but not the flag or the audio check", %{directory: dir} do
    assert Music.evaluate(manifest(), %{}, dir, enabled: true, audition: true) == :available
    assert {:unavailable, ["music is disabled"]} =
             Music.evaluate(manifest(), %{}, dir, enabled: false, audition: true)
  end

  test "a reviewed cross-region voyage handoff also requires its reverse", %{directory: dir} do
    one_way = update_in(approvals()["handoffs"], &Enum.reject(&1, fn h ->
      h["kind"] == "voyage-handoff" and h["from"] == "w" and h["to"] == "v"
    end))
    assert Music.approval_report(manifest(), one_way).pending == ["w → v voyage handoff"]
    assert {:unavailable, reasons} = Music.evaluate(manifest(), one_way, dir, enabled: true)
    assert "w → v voyage handoff pending" in reasons
  end

  test "self, port and unknown-track handoffs cannot stand in for cross-region review" do
    for {from, to} <- [{"v", "v"}, {"p", "w"}, {"v", "ghost"}] do
      tracks = manifest()["tracks"]
      invalid = approved(%{"kind" => "voyage-handoff", "from" => from, "to" => to,
        "from_output_sha256" => get_in(tracks, [from, "output_sha256"]),
        "to_output_sha256" => get_in(tracks, [to, "output_sha256"]), "recipe" => @recipe})
      records = update_in(approvals()["handoffs"], fn handoffs ->
        Enum.filter(handoffs, &(&1["kind"] == "port-to-voyage")) ++ [invalid]
      end)
      report = Music.approval_report(manifest(), records)
      assert "#{from} → #{to} voyage handoff outside cross-region voyage pools" in report.stale
      assert report.pending == ["cross-region voyage handoff"]
    end
  end

  test "two voyage tracks in the same palette do not satisfy cross-region review" do
    same_palette = put_in(manifest()["palettes"], [
      %{"id" => "east", "ports" => ["Busan"], "port" => ["p", "q"], "voyage" => ["v", "w"]}
    ])
    report = Music.approval_report(same_palette, approvals())
    assert "v → w voyage handoff outside cross-region voyage pools" in report.stale
    assert "w → v voyage handoff outside cross-region voyage pools" in report.stale
    assert "cross-region voyage handoff" in report.pending
  end

  test "the test build plays the approved fixture" do
    assert Music.status() == :available
    assert Music.manifest_url() == "/audio/fixtures/music.json"
  end
end
```

- [ ] **Step 3: Run to verify failure**

Run: `mix test test/tijara_tides_web/music_test.exs`
Expected: compile error, `TijaraTidesWeb.Music` undefined.

- [ ] **Step 4: Implement the module**

Create `lib/tijara_tides_web/music.ex`:

```elixir
defmodule TijaraTidesWeb.Music do
  @moduledoc """
  Whether the client may play background music, and the credits it shows.

  The soundtrack is presentation data. `priv/audio/music.json` lists palettes
  and tracks, the audio is stored in Git LFS, and `priv/music/approvals.json`
  records listening decisions bound to the exact files and playback recipe they
  were made against. The server never chooses pieces; it only gates playback.
  """
  require Logger

  @status_key {__MODULE__, :status}
  @audition_allowed Application.compile_env(:tijara_tides, :music_audition_allowed, false)

  def manifest_url, do: Keyword.fetch!(config(), :url)
  def manifest, do: read_json(priv(:manifest))

  @doc "Availability, computed once per boot."
  def status do
    with nil <- :persistent_term.get(@status_key, nil) do
      status = compute_status()
      :persistent_term.put(@status_key, status)
      status
    end
  end

  def log_status do
    with {:unavailable, reasons} <- status() do
      Logger.warning("Background music is unavailable: " <> Enum.join(reasons, "; "))
    end

    :ok
  end

  def evaluate(manifest, approvals, directory, opts) do
    reasons =
      if(Keyword.fetch!(opts, :enabled), do: [], else: ["music is disabled"]) ++
        missing_audio(manifest, directory) ++
        if(Keyword.get(opts, :audition, false), do: [], else: unapproved(manifest, approvals))

    if reasons == [], do: :available, else: {:unavailable, reasons}
  end

  def approval_report(manifest, approvals) do
    tracks = manifest["tracks"]
    recipe = manifest["recipe"]
    recorded = approvals["tracks"] || %{}
    handoffs = approvals["handoffs"] || []

    pairs =
      for palette <- manifest["palettes"], from <- palette["port"], to <- palette["voyage"],
          do: {from, to}

    track_items =
      for {slug, track} <- Enum.sort(tracks), part <- ["recording", "playback"] do
        {"#{slug} #{part}", classify(get_in(recorded, [slug, part]), binding(part, track, recipe))}
      end

    unknown =
      for slug <- Enum.sort(Map.keys(recorded)), not Map.has_key?(tracks, slug),
          do: {"#{slug} approvals for an unknown track", :stale}

    pair_items =
      for {from, to} <- pairs do
        entry = find_handoff(handoffs, "port-to-voyage", from, to)
        {"#{from} → #{to} handoff", classify(entry, handoff_binding(from, to, tracks, recipe, true))}
      end

    outside =
      for %{"kind" => "port-to-voyage"} = h <- handoffs, {h["from"], h["to"]} not in pairs,
          do: {"#{h["from"]} → #{h["to"]} handoff outside the roster", :stale}

    odd =
      for h <- handoffs, h["kind"] not in ["port-to-voyage", "voyage-handoff"],
          do: {"handoff of unknown kind #{inspect(h["kind"])}", :stale}

    voyages = voyage_items(handoffs, manifest["palettes"], tracks, recipe)
    (track_items ++ unknown ++ pair_items ++ outside ++ voyages ++ odd)
    |> Enum.group_by(&elem(&1, 1), &elem(&1, 0))
  end

  def credits(manifest) do
    base = Path.dirname(manifest_url())

    for palette <- manifest["palettes"], role <- ["port", "voyage"], slug <- palette[role] do
      track = manifest["tracks"][slug]

      %{
        slug: slug,
        palette: palette["name"],
        role: role,
        title: track["title"],
        credit: track["credit"],
        source_url: track["source_url"],
        licence: track["licence"],
        licence_url: track["licence_url"],
        edits: track["edits"],
        notices: for(n <- track["notices"] || [], do: %{name: n["name"], url: base <> "/" <> n["file"]})
      }
    end
  end

  defp voyage_items(handoffs, palettes, tracks, recipe) do
    voyage_palettes = Map.new(for p <- palettes, slug <- p["voyage"], do: {slug, p["id"]})
    recorded = Enum.filter(handoffs, &(&1["kind"] == "voyage-handoff"))
    {valid, invalid} = Enum.split_with(recorded, fn h ->
      origin = voyage_palettes[h["from"]]
      destination = voyage_palettes[h["to"]]
      Map.has_key?(tracks, h["from"]) and Map.has_key?(tracks, h["to"]) and
        origin != nil and destination != nil and origin != destination
    end)

    invalid_items = for h <- invalid do
      {"#{h["from"]} → #{h["to"]} voyage handoff outside cross-region voyage pools", :stale}
    end

    required = valid
      |> Enum.flat_map(fn h -> [{h["from"], h["to"]}, {h["to"], h["from"]}] end)
      |> Enum.uniq()
      |> Enum.sort()

    checks = for h <- valid do
      {"#{h["from"]} → #{h["to"]} voyage handoff",
       classify(h, handoff_binding(h["from"], h["to"], tracks, recipe, false))}
    end

    missing = for {from, to} <- required,
                  find_handoff(valid, "voyage-handoff", from, to) == nil do
      {"#{from} → #{to} voyage handoff", :pending}
    end

    empty = if valid == [], do: [{"cross-region voyage handoff", :pending}], else: []
    invalid_items ++ checks ++ missing ++ empty
  end

  defp find_handoff(handoffs, kind, from, to),
    do: Enum.find(handoffs, &(&1["kind"] == kind and &1["from"] == from and &1["to"] == to))

  defp binding("recording", track, _recipe), do: %{"source_sha256" => track["source_sha256"]}

  defp binding("playback", track, recipe),
    do: %{"output_sha256" => track["output_sha256"], "entry_s" => track["entry_s"], "recipe" => recipe}

  # Selection handoffs start at the voyage's entry; automatic handoffs at zero.
  defp handoff_binding(from, to, tracks, recipe, entry?) do
    binding = %{
      "from_output_sha256" => get_in(tracks, [from, "output_sha256"]),
      "to_output_sha256" => get_in(tracks, [to, "output_sha256"]),
      "recipe" => recipe
    }

    if entry?, do: Map.put(binding, "to_entry_s", get_in(tracks, [to, "entry_s"])), else: binding
  end

  defp classify(nil, _binding), do: :pending
  defp classify(%{"decision" => "pending"}, _binding), do: :pending
  defp classify(%{"decision" => "rejected"}, _binding), do: :rejected

  defp classify(%{"decision" => "approved"} = entry, binding),
    do: if(Map.take(entry, Map.keys(binding)) == binding, do: :approved, else: :stale)

  defp classify(_entry, _binding), do: :stale

  defp unapproved(manifest, approvals) do
    report = approval_report(manifest, approvals)
    for status <- [:stale, :rejected, :pending], item <- Map.get(report, status, []), do: "#{item} #{status}"
  end

  defp missing_audio(manifest, directory) do
    for {_slug, track} <- Enum.sort(manifest["tracks"]), not ogg?(Path.join(directory, track["file"])),
        do: "#{track["file"]} is not Ogg audio (missing or a Git LFS pointer)"
  end

  defp ogg?(path), do: match?({:ok, "OggS"}, File.open(path, [:read, :binary], &IO.binread(&1, 4)))

  defp compute_status do
    with {:ok, manifest} <- manifest(),
         {:ok, approvals} <- read_json(priv(:approvals)) do
      evaluate(manifest, approvals, Path.dirname(priv(:manifest)),
        enabled: Keyword.get(config(), :enabled, false),
        audition: @audition_allowed and Keyword.get(config(), :audition, false)
      )
    else
      {:error, reason} -> {:unavailable, [reason]}
    end
  end

  defp read_json(path) do
    with {:ok, body} <- File.read(path),
         {:ok, json} <- Jason.decode(body) do
      {:ok, json}
    else
      {:error, %Jason.DecodeError{} = error} ->
        {:error, "#{Path.basename(path)} is not valid JSON: #{Exception.message(error)}"}

      {:error, reason} ->
        {:error, "#{Path.basename(path)} cannot be read: #{:file.format_error(reason)}"}
    end
  end

  defp config, do: Application.get_env(:tijara_tides, :music, [])
  defp priv(key), do: Application.app_dir(:tijara_tides, Path.join("priv", Keyword.fetch!(config(), key)))
end
```

In `lib/tijara_tides_web.ex`, change `exports: [Endpoint, Telemetry]` to
`exports: [Endpoint, Telemetry, Music]`. In `lib/tijara_tides/application.ex`,
add after `TijaraTidesWeb.Endpoint,`:

```elixir
          {Task, &TijaraTidesWeb.Music.log_status/0},
```

- [ ] **Step 5: Serve the soundtrack**

In `lib/tijara_tides_web/endpoint.ex`, immediately before the existing
`plug Plug.Static,` add:

```elixir
  # Background music lives outside priv/static so phx.digest does not ship a
  # fingerprinted second copy of every recording. Range requests are served.
  plug Plug.Static, at: "/audio", from: {:tijara_tides, "priv/audio"}, gzip: false
```

Add to `test/tijara_tides_web/music_test.exs` (needs the endpoint, so a new
module in the same file):

```elixir
defmodule TijaraTidesWeb.MusicServingTest do
  use TijaraTidesWeb.ConnCase, async: true

  test "audio supports byte ranges and full downloads", %{conn: conn} do
    path = Application.app_dir(:tijara_tides, "priv/audio/fixtures/east-port.ogg")
    bytes = File.read!(path)

    partial = conn |> put_req_header("range", "bytes=4-19") |> get("/audio/fixtures/east-port.ogg")
    assert partial.status == 206
    assert get_resp_header(partial, "content-range") == ["bytes 4-19/#{byte_size(bytes)}"]
    assert partial.resp_body == binary_part(bytes, 4, 16)

    full = build_conn() |> get("/audio/fixtures/east-port.ogg")
    assert full.status == 200 and full.resp_body == bytes
    assert ["audio/ogg" <> _] = get_resp_header(full, "content-type")
    assert build_conn() |> get("/audio/fixtures/music.json") |> json_response(200)
  end
end
```

- [ ] **Step 6: Run the unit and serving tests**

Run: `mix test test/tijara_tides_web/music_test.exs`
Expected: all pass, no warnings.

- [ ] **Step 7: Manifest and approvals docs tests**

Create `test/docs/music_manifest_test.exs`:

```elixir
defmodule Docs.MusicManifestTest do
  @moduledoc """
  Guards the committed soundtrack manifest against the catalogue, DESIGN.md's
  palette table and the files beside it. Files are compared by SHA-256 either
  directly or through their Git LFS pointer, so CI checks hashes without
  downloading audio.
  """
  use ExUnit.Case, async: true

  @manifest "priv/audio/music.json"
  @pointer "version https://git-lfs.github.com/spec/v1\n"

  defp manifest, do: @manifest |> File.read!() |> Jason.decode!()

  defp identity(path) do
    case File.read(path) do
      {:ok, @pointer <> _ = pointer} ->
        [_, oid] = Regex.run(~r/^oid sha256:([0-9a-f]{64})$/m, pointer)
        oid

      {:ok, bytes} ->
        :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)

      {:error, reason} ->
        flunk("#{path}: #{reason}")
    end
  end

  defp design_palettes do
    File.read!("docs/DESIGN.md")
    |> String.split("| Palette | Ports |\n", parts: 2)
    |> List.last()
    |> String.split("\n")
    |> Enum.take_while(&String.starts_with?(&1, "|"))
    |> Enum.reject(&String.starts_with?(&1, "|---"))
    |> Enum.map(fn line ->
      [name, ports] = line |> String.split("|", trim: true) |> Enum.map(&String.trim/1)
      {name, ports |> String.split(", ") |> Enum.sort()}
    end)
  end

  test "every catalogue port appears in exactly one palette" do
    ports = File.read!("priv/game/catalogue.json") |> Jason.decode!() |> Map.fetch!("ports") |> Map.keys() |> Enum.sort()
    listed = Enum.flat_map(manifest()["palettes"], & &1["ports"])
    assert Enum.sort(listed) == ports
    assert length(listed) == length(Enum.uniq(listed))
  end

  test "palettes match DESIGN.md's table and every pool is populated" do
    palettes = manifest()["palettes"]
    assert length(palettes) == 12

    assert design_palettes() ==
             for(p <- palettes, do: {p["name"], Enum.sort(p["ports"])})

    for p <- palettes, role <- ["port", "voyage"] do
      assert p[role] != [], "#{p["id"]} has no #{role} track"
      assert Enum.all?(p[role], &Map.has_key?(manifest()["tracks"], &1))
    end

    assert map_size(manifest()["tracks"]) == 28
  end

  test "every track is credited and its files match their recorded hashes" do
    for {slug, track} <- manifest()["tracks"] do
      for key <- ~w(title credit source_url licence licence_url edits),
          do: assert(is_binary(track[key]) and track[key] != "", "#{slug} lacks #{key}")

      assert [_ | _] = track["artists"]
      assert identity(Path.join("priv/audio", track["file"])) == track["output_sha256"], slug
      assert track["entry_s"] >= 0 and track["entry_s"] < track["duration_s"]
      assert is_number(track["true_peak_dbtp"])
      assert track["true_peak_dbtp"] <= manifest()["recipe"]["true_peak_dbtp"]

      for notice <- track["notices"], do: assert(File.exists?(Path.join("priv/audio", notice["file"])))
    end
  end
end
```

Create `test/docs/music_approvals_test.exs`:

```elixir
defmodule Docs.MusicApprovalsTest do
  @moduledoc """
  A recorded approval must still describe the files and recipe it approved, so
  a stale sign-off fails in the change that made it stale. Pending approvals
  pass and are listed; they only keep production music unavailable.
  """
  use ExUnit.Case, async: true

  defp json(path), do: path |> File.read!() |> Jason.decode!()

  test "no listening approval is stale" do
    report = TijaraTidesWeb.Music.approval_report(json("priv/audio/music.json"), json("priv/music/approvals.json"))
    assert Map.get(report, :stale, []) == []

    for status <- [:pending, :rejected], item <- Map.get(report, status, []),
        do: IO.puts("music approval #{status}: #{item}")
  end

  test "the fixture soundtrack is fully approved" do
    report =
      TijaraTidesWeb.Music.approval_report(
        json("priv/audio/fixtures/music.json"),
        json("priv/music/fixtures/approvals.json")
      )

    assert Map.keys(report) == [:approved]
  end
end
```

The pending list prints dozens of lines until Task 15; that output is the
"listed" requirement. If `scripts/check-local.sh` treats test stdout as noise,
keep it: it is the release gate's visible to-do list.

- [ ] **Step 8: Run and break**

Run: `mix test test/docs/music_manifest_test.exs test/docs/music_approvals_test.exs`
Expected: pass. Then:
- remove `"Colón"` from the Caribbean palette in `priv/audio/music.json` →
  the catalogue test fails; restore;
- add `"stale": {"recording": {"decision": "approved"}}` under `tracks` in
  `priv/music/approvals.json` → the approvals test fails; restore;
- change one hex digit of a track's `output_sha256` → the files test fails;
  restore.
- Remove the missing-reverse check from `voyage_items` → the one-way
  handoff test fails; restore. Accept every recorded voyage handoff as valid
  without checking its pool or palette → the invalid-pair tests fail; restore.

- [ ] **Step 9: Document**

Add to `docs/architecture.md` immediately before `## Localization boundary`:

```markdown
## Background music

Background music is client-side presentation. The server stores no music state
in the world: GameLive records the player's latest explicit ship or port focus
and renders the resulting musical context as data attributes, and
`TijaraTidesWeb.Music` decides whether the client may play at all. Playback
requires the `TIJARA_MUSIC_ENABLED` flag, real Ogg files rather than Git LFS
pointers, and listening approvals in `priv/music/approvals.json` that still
match the manifest's source and output hashes, entry offsets and playback
recipe. The result is computed once per boot and logged when music is
unavailable. `scripts/prepare-music.py` writes the manifest and audio but never
the approvals file. The soundtrack is served from `priv/audio` by its own
`Plug.Static` at `/audio`, outside `phx.digest`.
```

Replace the first paragraph of `docs/music-recording-audit.md` (the "Local-file
index updated…" paragraph) with:

```markdown
Local-file index updated on 11 October 2026 after the authorized generated-audio
cleanup; see [local evidence and previews](#local-evidence-and-previews). The
shipped soundtrack is prepared by `scripts/prepare-music.py` from
`scripts/music-roster.json`, and release listening approvals are recorded in
`priv/music/approvals.json`, which binds each decision to the exact files it
was made against.
```

- [ ] **Step 10: Gates and commit**

Run `mix precommit` and `python3 scripts/test-game-db.py`; confirm zero
warnings (`grep -c warning` on the output is 0). Then:

```bash
git add lib config test docs
git commit -m "Gate background music on files, flag and approvals

Adds the availability check, serves priv/audio at /audio with range
support, and tests the manifest against the catalogue, DESIGN.md and
its files, and every recorded approval against its binding.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Deploy and measure the LFS download (stop point)

**Files:**
- Modify: `docs/deploying.md`

This step pushes LFS objects to GitHub and triggers a Render deploy, both
outward-facing. **Ask the user before pushing.**

- [ ] **Step 1: Record the baseline**

Ask the user to open GitHub → Settings → Billing → Usage, filter to Git LFS,
and report current bandwidth for this month.

- [ ] **Step 2: Push**

```bash
git push origin main
```

The pre-push hook runs full validation, then uploads 30 LFS objects. Wait for
CI to pass and Render to deploy (`autoDeployTrigger: checksPass`).

- [ ] **Step 3: Check serving on Render**

With the deployed host as `$HOST`:

```bash
curl -s -o /dev/null -w '%{http_code} %{content_type}\n' -H 'Range: bytes=0-99' "https://$HOST/audio/shenyang.ogg"
curl -s -H 'Range: bytes=0-3' "https://$HOST/audio/shenyang.ogg" | head -c 4; echo
curl -sI -H 'Range: bytes=0-99' "https://$HOST/audio/shenyang.ogg" | grep -i content-range
```

Expected: `206 audio/ogg`, then `OggS`, then `content-range: bytes 0-99/<size>`.
If the body begins `vers`, Render served an LFS pointer: **stop and report**
(the deploy did not fetch LFS; music would stay unavailable).

- [ ] **Step 4: Measure**

Ask the user to read the LFS bandwidth again after the deploy finished.
Compute the deploy's download (expect about 37 MB, or near zero if Render
cached). Project the month: deploys per month (227 pushes last month) times
the per-deploy figure. **If the projection exceeds 8 GiB, stop** and ask
whether to set an LFS budget or change deployment before continuing.

- [ ] **Step 5: Record and commit**

Append to the `## Background music files` section in `docs/deploying.md` a
paragraph stating the date, the measured per-deploy LFS download, whether
range requests returned 206 through Render, and the projected monthly
bandwidth. Rewrap the paragraph. Commit:

```bash
git add docs/deploying.md
git commit -m "Record Render's measured LFS download for music

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Music credits page

**Files:**
- Create: `lib/tijara_tides_web/controllers/music_credits_controller.ex`
- Create: `lib/tijara_tides_web/controllers/music_credits_html.ex`
- Modify: `lib/tijara_tides_web/router.ex`
- Create: `test/tijara_tides_web/controllers/music_credits_controller_test.exs`
- Modify: `priv/gettext/default.pot` (extract), `priv/gettext/ar/LC_MESSAGES/default.po`

**Interfaces:**
- Consumes: `Music.manifest/0`, `Music.credits/1`.
- Produces: route `GET /music/credits` (used by Task 8's popover link).

- [ ] **Step 1: Failing test**

```elixir
defmodule TijaraTidesWeb.MusicCreditsControllerTest do
  use TijaraTidesWeb.ConnCase, async: true

  test "lists every track's title, creators, source, licence and edits", %{conn: conn} do
    html = conn |> get("/music/credits") |> html_response(200)
    {:ok, manifest} = TijaraTidesWeb.Music.manifest()

    for {slug, track} <- manifest["tracks"] do
      assert html =~ ~s(id="music-credit-#{slug}")
      for key <- ~w(title credit source_url licence edits), do: assert(html =~ track[key])
    end

    assert html =~ "Music credits"
  end
end
```

Run: `mix test test/tijara_tides_web/controllers/music_credits_controller_test.exs`
Expected: FAIL, 404 / no route.

- [ ] **Step 2: Implement**

Router, in the `pipe_through :browser` scope after `live "/play", GameLive`:

```elixir
    get "/music/credits", MusicCreditsController, :show
```

`lib/tijara_tides_web/controllers/music_credits_controller.ex`:

```elixir
defmodule TijaraTidesWeb.MusicCreditsController do
  use TijaraTidesWeb, :controller

  def show(conn, _params) do
    case TijaraTidesWeb.Music.manifest() do
      {:ok, manifest} ->
        render(conn, :show,
          page_title: gettext("Music credits"),
          tracks: TijaraTidesWeb.Music.credits(manifest)
        )

      {:error, _reason} ->
        conn |> put_status(:not_found) |> text(gettext("Music credits are unavailable."))
    end
  end
end
```

`lib/tijara_tides_web/controllers/music_credits_html.ex`:

```elixir
defmodule TijaraTidesWeb.MusicCreditsHTML do
  use TijaraTidesWeb, :html

  def show(assigns) do
    ~H"""
    <main id="music-credits" class="mx-auto max-w-3xl p-6">
      <h1 class="text-2xl font-semibold">{gettext("Music credits")}</h1>
      <p class="mt-2 text-sm text-slate-300">{gettext("The soundtrack uses these recordings.")}</p>
      <article
        :for={track <- @tracks}
        id={"music-credit-" <> track.slug}
        class="mt-6 rounded-xl border border-slate-700 p-4"
      >
        <h2 class="text-lg" dir="auto">{track.title}</h2>
        <dl class="mt-2 grid grid-cols-[auto_1fr] gap-x-4 gap-y-1 text-sm">
          <dt>{gettext("Credited creators")}</dt>
          <dd dir="auto">{track.credit}</dd>
          <dt>{gettext("Source")}</dt>
          <dd><a class="underline" href={track.source_url} rel="noopener noreferrer">{track.source_url}</a></dd>
          <dt>{gettext("License")}</dt>
          <dd><a class="underline" href={track.licence_url} rel="noopener noreferrer">{track.licence}</a></dd>
          <dt>{gettext("Edits")}</dt>
          <dd>{track.edits}</dd>
          <%= if track.notices != [] do %>
            <dt>{gettext("Supplied notice")}</dt>
            <dd><a :for={notice <- track.notices} class="underline" href={notice.url}>{notice.name}</a></dd>
          <% end %>
        </dl>
      </article>
      <a href={~p"/play"} class="mt-8 inline-block underline">{gettext("Back to the game")}</a>
    </main>
    """
  end
end
```

- [ ] **Step 3: Translations**

Run `mix gettext.extract`. Append to `priv/gettext/ar/LC_MESSAGES/default.po`
(keep existing entries; never run `mix gettext.merge`):

```po
msgid "Music credits"
msgstr "اعتمادات الموسيقى"

msgid "Music credits are unavailable."
msgstr "اعتمادات الموسيقى غير متاحة."

msgid "The soundtrack uses these recordings."
msgstr "تستخدم الموسيقى التصويرية هذه التسجيلات."

msgid "Credited creators"
msgstr "المبدعون المذكورون"

msgid "Source"
msgstr "المصدر"

msgid "License"
msgstr "الترخيص"

msgid "Edits"
msgstr "التعديلات"

msgid "Supplied notice"
msgstr "الإشعار المرفق"

msgid "Back to the game"
msgstr "العودة إلى اللعبة"
```

Skip any msgid that already exists in the Arabic file (grep first). Run
`python3 scripts/check-gettext-catalogues.py`; expected: pass.

- [ ] **Step 4: Run, break, gates, commit**

Run the controller test; expected PASS. Remove the `{track.edits}` cell,
rerun, expect failure, restore. Run `mix precommit` and
`python3 scripts/test-game-db.py` (zero warnings).

```bash
git add lib test priv/gettext
git commit -m "Add the music credits page

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: Explicit music focus and the header element

**Files:**
- Create: `lib/tijara_tides_web/components/game/music_panel.ex`
- Modify: `lib/tijara_tides_web/live/game_live.ex` (mount ~line 35, events at ~439–462 and ~570–603, `apply_view` ~1424, header render ~1564)
- Create: `test/tijara_tides_web/components/music_panel_test.exs`
- Create: `test/tijara_tides/infrastructure/music_focus_test.exs`
- Modify: `assets/css/app.css`, gettext files, `docs/architecture.md`

**Interfaces:**
- Consumes: `Music.status/0`, `Music.manifest_url/0`, route `/music/credits`,
  `GameQueries.voyage_progress/2`.
- Produces:
  - `MusicPanel.focus(focus | nil, view, selected_port) :: {:port, String.t()} | {:ship, String.t()}`
  - `MusicPanel.context(view, focus) :: %{String.t() => String.t()}`
  - `MusicPanel.ship(view, id) :: map | nil`
  - DOM: `#music` with `data-music` (`available|unavailable`), `data-manifest`,
    `data-context` (`port|voyage`), `data-port`, `data-ship`, `data-origin`,
    `data-destination`, `data-progress` (4 decimals), `data-now-playing`,
    `data-label-on`, `data-label-off`; inside it `#music-controls`
    (`phx-update="ignore"`) with `#music-toggle`, `#music-settings`,
    `#music-volume`, and `#music-credit`. No `phx-hook` yet (Task 12 adds it).

- [ ] **Step 1: Failing component unit test**

`test/tijara_tides_web/components/music_panel_test.exs`:

```elixir
defmodule TijaraTidesWeb.GameUI.MusicPanelTest do
  use ExUnit.Case, async: true
  alias TijaraTidesWeb.GameUI.MusicPanel

  @view %{
    private: %{"ships" => %{"c:1" => %{"id" => "c:1", "status" => "loading", "port" => "Busan"}}},
    public: %{
      "clock_ms" => 0,
      "ships" => %{"d:1" => %{"id" => "d:1", "status" => "docked", "port" => "Dubai"}}
    }
  }

  test "initial focus is the selected port after the first view" do
    assert MusicPanel.focus(nil, @view, "Tokyo") == {:port, "Tokyo"}
  end

  test "a focused ship that left the view falls back to the selected port" do
    assert MusicPanel.focus({:ship, "gone:9"}, @view, "Tokyo") == {:port, "Tokyo"}
    assert MusicPanel.focus({:ship, "c:1"}, @view, "Tokyo") == {:ship, "c:1"}
    assert MusicPanel.focus({:ship, "d:1"}, %{@view | private: nil}, "Tokyo") == {:ship, "d:1"}
    assert MusicPanel.focus({:port, "Athens"}, @view, "Tokyo") == {:port, "Athens"}
  end

  test "ships in port present their port; port focus keeps its own identifier" do
    assert MusicPanel.context(@view, {:ship, "c:1"}) == %{"context" => "port", "port" => "Busan"}
    assert MusicPanel.context(@view, {:ship, "d:1"}) == %{"context" => "port", "port" => "Dubai"}
    assert MusicPanel.context(@view, {:port, "Athens"}) == %{"context" => "port", "port" => "Athens"}
  end
end
```

Run it; expected: FAIL (module undefined).

- [ ] **Step 2: The component**

`lib/tijara_tides_web/components/game/music_panel.ex`:

```elixir
defmodule TijaraTidesWeb.GameUI.MusicPanel do
  @moduledoc """
  Header music controls. GameLive owns `music_focus`, the player's latest
  explicit ship or port selection; this component renders the musical context
  that focus implies, which the client's Music hook follows.
  """
  use TijaraTidesWeb, :html
  alias TijaraTides.UseCases.GameQueries

  attr :view, :any, required: true
  attr :focus, :any, required: true

  def panel(assigns) do
    assigns =
      assign(assigns,
        context: context(assigns.view, assigns.focus),
        available: TijaraTidesWeb.Music.status() == :available
      )

    ~H"""
    <div
      id="music"
      class="music-control"
      data-music={if @available, do: "available", else: "unavailable"}
      data-manifest={TijaraTidesWeb.Music.manifest_url()}
      data-context={@context["context"]}
      data-port={@context["port"]}
      data-ship={@context["ship"]}
      data-origin={@context["origin"]}
      data-destination={@context["destination"]}
      data-progress={@context["progress"]}
      data-now-playing={
        gettext("Now playing: %{title} by %{artists}", title: "%{title}", artists: "%{artists}")
      }
      data-label-on={gettext("Turn music on")}
      data-label-off={gettext("Turn music off")}
    >
      <div id="music-controls" class="music-controls" phx-update="ignore" hidden={!@available}>
        <button
          type="button"
          id="music-toggle"
          class="popup-menu-trigger"
          aria-pressed="true"
          aria-label={gettext("Turn music off")}
        >🔊</button>
        <details id="music-settings" class="music-settings">
          <summary class="popup-menu-trigger" aria-label={gettext("Music settings")}>♪</summary>
          <div class="music-popover">
            <label for="music-volume">{gettext("Music volume")}</label>
            <input id="music-volume" type="range" min="0" max="100" step="1" value="30" />
            <a href={~p"/music/credits"} target="_blank" rel="noopener" class="underline">
              {gettext("Music credits")}
            </a>
          </div>
        </details>
        <div aria-live="polite">
          <a id="music-credit" class="music-credit" hidden target="_blank" rel="noopener noreferrer" dir="auto"></a>
        </div>
      </div>
    </div>
    """
  end

  @doc "The retained focus after a view refresh."
  def focus(nil, _view, port), do: {:port, port}
  def focus({:ship, id} = focus, view, port), do: if(ship(view, id), do: focus, else: {:port, port})
  def focus(focus, _view, _port), do: focus

  def context(_view, {:port, port}), do: %{"context" => "port", "port" => port}

  def context(view, {:ship, id}) do
    case ship(view, id) do
      %{"status" => "sailing"} = ship ->
        progress =
          ship |> GameQueries.voyage_progress(view.public["clock_ms"]) |> max(0.0) |> min(1.0)

        %{
          "context" => "voyage",
          "ship" => id,
          "origin" => ship["port"],
          "destination" => ship["destination"],
          "progress" => :erlang.float_to_binary(progress * 1.0, decimals: 4)
        }

      %{} = ship ->
        %{"context" => "port", "port" => ship["port"]}

      nil ->
        %{}
    end
  end

  def ship(view, id), do: (view.private && view.private["ships"][id]) || view.public["ships"][id]
end
```

Run the unit test; expected: PASS.

- [ ] **Step 3: Failing GameLive test**

`test/tijara_tides/infrastructure/music_focus_test.exs`:

```elixir
defmodule TijaraTides.Infrastructure.MusicFocusTest do
  use ExUnit.Case, async: false
  @moduletag :game_database
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  alias TijaraTides.SqlReplay, as: Sql
  alias TijaraTides.Infrastructure.GameServer
  @endpoint TijaraTidesWeb.Endpoint

  setup_all do
    Sql.repo()
  end

  defp music(view) do
    node = view |> render() |> LazyHTML.from_fragment() |> LazyHTML.query("#music")

    for name <- ~w(music context port ship origin destination progress), into: %{} do
      {name, node |> LazyHTML.attribute("data-" <> name) |> List.first()}
    end
  end

  defp refreshed(view) do
    send(view.pid, {:game_changed, 0})
    render_async(view)
    music(view)
  end

  defp status(token, c, ship), do: GameServer.snapshot(token, c.server).public["ships"][ship]["status"]

  defp progress(attrs) do
    {value, ""} = Float.parse(attrs["progress"])
    assert value >= 0.0 and value <= 1.0
    value
  end

  # Advances until `done?` holds, failing after a bounded number of steps.
  defp advance_until(c, step_ms, done?) do
    Enum.find_value(1..200, fn _ ->
      Sql.advance(c.server, step_ms)
      done?.()
    end) || flunk("condition not reached")
  end

  test "music follows explicit selections, departures, diversions and arrivals" do
    Sql.with_world(fn c ->
      {conn, token} = TijaraTides.WebFormFixture.session(c)

      {:ok, visitor, _} = build_conn() |> live("/play")
      assert %{"music" => "available", "context" => "port", "port" => "Guangzhou", "ship" => nil} =
               music(visitor)

      {:ok, %{"company_id" => company}} =
        TijaraTides.CompanyFixture.command(
          token,
          "formation",
          %{"action" => "company", "name" => "Music Owners", "port" => "Jakarta", "package" => "general"},
          c.server
        )

      ship = company <> ":1"
      {:ok, view, _} = conn |> recycle() |> live("/play")
      # The first view auto-selects the docked ship; focus starts at its port.
      assert %{"context" => "port", "port" => "Jakarta"} = music(view)

      render_click(view, "port", %{"id" => "Tangier"})
      assert %{"context" => "port", "port" => "Tangier"} = music(view)

      # A destination preview moves selected_port to the ship's port; music stays.
      render_click(view, "preview", %{"destination" => "Singapore"})
      assert has_element?(view, ~s(#port-selector[data-selected="Jakarta"]))
      assert %{"port" => "Tangier"} = music(view)

      render_click(view, "ship", %{"id" => ship})
      assert %{"context" => "port", "port" => "Jakarta", "ship" => nil} = music(view)

      Sql.command(c, token, "sail", %{
        "action" => "sail",
        "ship" => ship,
        "destination" => "Singapore",
        "fuel_limit" => 1_000_000_000
      })

      voyage = refreshed(view)

      assert %{"context" => "voyage", "ship" => ^ship, "origin" => "Jakarta", "destination" => "Singapore"} =
               voyage

      early = progress(voyage)
      # Routine refreshes keep the ship's context while progress moves.
      later = advance_until(c, 600_000, fn -> (p = progress(refreshed(view))) > early && p end)

      # A visitor's explicit inspection of a public sailing ship is a ship focus too.
      refreshed(visitor)
      render_click(visitor, "inspect-ship", %{"id" => ship})
      assert %{"context" => "voyage", "ship" => ^ship, "origin" => "Jakarta"} = music(visitor)

      Sql.command(c, token, "reroute", %{
        "action" => "reroute",
        "ship" => ship,
        "destination" => "Ho Chi Minh City",
        "fuel_limit" => 1_000_000_000
      })

      diverted = refreshed(view)
      assert %{"origin" => "Jakarta", "destination" => "Ho Chi Minh City"} = diverted
      assert progress(diverted) < later

      advance_until(c, 3_600_000, fn -> status(token, c, ship) != "sailing" end)
      assert %{"context" => "port", "port" => "Ho Chi Minh City", "ship" => nil} = refreshed(view)
    end)
  end
end
```

If the reroute command is refused for Ho Chi Minh City from the ship's
position, use another reachable port and adjust the two assertions; the
contract under test is "origin stays, destination changes, progress resets".

Run: `python3 scripts/test-game-db.py test/tijara_tides/infrastructure/music_focus_test.exs`
(or the script's single-file option; see its `--help`). Expected: FAIL, no
`#music` element.

- [ ] **Step 4: Wire GameLive**

In `mount/3`'s assign list add `music_focus: nil,` after `selected_port: "Guangzhou",`.

Events:

```elixir
  def handle_event("auction-port", %{"id" => id}, socket) do
    if socket.assigns.definitions.catalogue["ports"][id],
      do:
        {:noreply,
         socket
         |> assign(selected_port: id, music_focus: {:port, id})
         |> push_event("workspace-panel", %{panel: 2})},
      else: {:noreply, socket}
  end

  def handle_event("port", %{"id" => id}, socket) do
    if socket.assigns.definitions.catalogue["ports"][id],
      do:
        {:noreply,
         assign(socket, selected_port: id, first_ship_port_selected: true, music_focus: {:port, id})},
      else: {:noreply, socket}
  end
```

In `"first-ship-port"`, change the success assign to
`assign(socket, selected_port: id, first_ship_port_selected: true, music_focus: {:port, id})`.

In `"inspect-ship"`, the public branch becomes:

```elixir
      ship = socket.assigns.view.public["ships"][id] ->
        {:noreply,
         socket
         |> assign(inspected_ship: id, music_focus: {:ship, id})
         |> reveal_public_ship(ship)}
```

In `"ship"`, add `music_focus: {:ship, id},` to the assign list.

In `apply_view`, add to the final `assign(` list (after `trade_context: context`):

```elixir
      music_focus:
        TijaraTidesWeb.GameUI.MusicPanel.focus(
          socket.assigns.music_focus,
          view,
          socket.assigns.selected_port
        )
```

In `render/1`, make the first child of `<div :if={@view.status == :ready} class="game-header-actions">`:

```heex
            <TijaraTidesWeb.GameUI.MusicPanel.panel view={@view} focus={@music_focus} />
```

- [ ] **Step 5: CSS**

Append to `assets/css/app.css`:

```css
/* Background music controls in the game header. */
.music-control { position: relative; display: flex; align-items: center; }
.music-controls { display: flex; align-items: center; gap: 4px; }
.music-controls[hidden], .music-credit[hidden] { display: none; }
.music-settings > summary { list-style: none; }
.music-settings > summary::-webkit-details-marker { display: none; }
.music-popover { position: absolute; inset-inline-end: 0; top: calc(100% + 4px); z-index: 50; display: grid; gap: 8px; min-width: 14rem; padding: 12px; border: 1px solid #475569; border-radius: 6px; background: #0f172a; font-size: 14px; }
.music-credit { position: fixed; top: 8px; left: 50%; transform: translateX(-50%); z-index: 60; max-width: min(90vw, 36rem); padding: 4px 12px; border: 1px solid #475569; border-radius: 6px; background: #0f172a; color: #99f6e4; font-size: 14px; text-align: center; }
```

- [ ] **Step 6: Translations**

Run `mix gettext.extract`, then append to the Arabic catalogue:

```po
msgid "Now playing: %{title} by %{artists}"
msgstr "يُعزف الآن: %{title} من إبداع %{artists}"

msgid "Turn music on"
msgstr "تشغيل الموسيقى"

msgid "Turn music off"
msgstr "إيقاف الموسيقى"

msgid "Music settings"
msgstr "إعدادات الموسيقى"

msgid "Music volume"
msgstr "مستوى صوت الموسيقى"
```

Run `python3 scripts/check-gettext-catalogues.py`.

- [ ] **Step 7: Run and break**

Run the focus DB test and the component test; expected PASS. Break once each:
- add `music_focus: {:port, socket.assigns.ship["port"]}` to the `"preview"`
  assign → the focus test fails at the preview assertion; restore;
- remove `music_focus` from the `"ship"` handler → fails at the ship
  assertion; restore;
- change `focus({:ship, id} = focus, …)` to always return `focus` → the
  fallback unit test fails; restore.

- [ ] **Step 8: Document**

In `docs/architecture.md`'s `## Background music` section, append a paragraph:

```markdown
`music_focus` holds `{:port, id}` or `{:ship, id}` and changes only on
successful explicit events: `port`, `auction-port`, `first-ship-port`, `ship`
and `inspect-ship`. Automatic `selected_port` changes never touch it, refreshes
retain it, and a focused ship that leaves the accessible view falls back once to
the selected port. The `#music` element's data attributes carry a port context,
or a voyage's ship, origin, destination and weather-aware progress from
`GameQueries.voyage_progress/2`.
```

- [ ] **Step 9: Gates and commit**

`mix precommit`; `python3 scripts/test-game-db.py`; zero warnings.

```bash
git add lib test assets/css/app.css priv/gettext docs/architecture.md
git commit -m "Track explicit music focus and render the musical context

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: Piece policy

**Files:**
- Create: `assets/js/music_policy.js`
- Create: `test/desktop/music-policy.test.mjs`

**Interfaces:**
- Produces:
  - `paletteOf(manifest, port) -> string | null`
  - `readContext(dataset) -> {kind: 'port', port} | {kind: 'voyage', ship, origin, destination, progress} | null`
  - `identity(manifest, context) -> 'port:<palette>' | 'voyage:<origin>><destination>' | null`
  - `choosePiece(manifest, context, previous, random) -> slug | null`

- [ ] **Step 1: Failing tests**

```js
import {test} from 'node:test'
import assert from 'node:assert/strict'
import {readFileSync} from 'node:fs'
const source = readFileSync(new URL('../../assets/js/music_policy.js', import.meta.url), 'utf8')
const policy = await import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`)

const manifest = {
  palettes: [
    {id: 'east', ports: ['Shanghai', 'Busan'], port: ['east-port'], voyage: ['east-voyage']},
    {id: 'west', ports: ['Tangier', 'Valencia'], port: ['west-a', 'west-b'], voyage: ['west-voyage']},
  ],
}
const port = p => ({kind: 'port', port: p})
const voyage = (origin, destination, progress) => ({kind: 'voyage', ship: 's', origin, destination, progress})

test('ports in one palette share an identity; voyages are palette pairs', () => {
  assert.equal(policy.identity(manifest, port('Tangier')), policy.identity(manifest, port('Valencia')))
  assert.notEqual(policy.identity(manifest, port('Tangier')), policy.identity(manifest, port('Shanghai')))
  assert.equal(policy.identity(manifest, voyage('Busan', 'Tangier', 0.1)),
    policy.identity(manifest, voyage('Shanghai', 'Valencia', 0.9)))
  assert.equal(policy.identity(manifest, voyage('Busan', 'Tangier', 0)), 'voyage:east>west')
})

test('unknown ports have no identity and no piece', () => {
  assert.equal(policy.identity(manifest, port('Atlantis')), null)
  assert.equal(policy.identity(manifest, voyage('Busan', 'Atlantis', 0.5)), null)
  assert.equal(policy.identity(manifest, null), null)
  assert.equal(policy.choosePiece(manifest, port('Atlantis'), null, () => 0), null)
})

test('progress 0 always chooses the origin and progress 1 the destination', () => {
  for (const r of [0, 0.25, 0.5, 0.999]) {
    assert.equal(policy.choosePiece(manifest, voyage('Busan', 'Tangier', 0), null, () => r), 'east-voyage')
    assert.equal(policy.choosePiece(manifest, voyage('Busan', 'Tangier', 1), null, () => r), 'west-voyage')
  }
  assert.equal(policy.choosePiece(manifest, voyage('Busan', 'Shanghai', 0.5), null, () => 0.9), 'east-voyage')
})

test('no immediate repeat when the pool offers another piece', () => {
  for (const r of [0, 0.5, 0.99]) assert.equal(policy.choosePiece(manifest, port('Tangier'), 'west-a', () => r), 'west-b')
  assert.equal(policy.choosePiece(manifest, port('Busan'), 'east-port', () => 0.5), 'east-port')
})

test('reads the server context from data attributes', () => {
  assert.deepEqual(policy.readContext({context: 'port', port: 'Tangier'}), port('Tangier'))
  assert.deepEqual(policy.readContext({context: 'voyage', ship: 's', origin: 'Busan', destination: 'Tangier', progress: '1.5'}),
    voyage('Busan', 'Tangier', 1))
  assert.equal(policy.readContext({context: 'voyage', origin: 'Busan', progress: 'x'}), null)
  assert.equal(policy.readContext({}), null)
})
```

Run: `node --test test/desktop/music-policy.test.mjs` → FAIL (file missing).

- [ ] **Step 2: Implement**

```js
// Pure rules mapping the server's musical context onto the soundtrack manifest.

export function paletteOf(manifest, port) {
  return manifest.palettes.find(palette => palette.ports.includes(port))?.id ?? null
}

export function readContext(dataset) {
  if (dataset.context === 'port') return dataset.port ? {kind: 'port', port: dataset.port} : null
  if (dataset.context !== 'voyage') return null
  const progress = Number(dataset.progress)
  if (!dataset.origin || !dataset.destination || !Number.isFinite(progress)) return null
  return {kind: 'voyage', ship: dataset.ship, origin: dataset.origin, destination: dataset.destination,
    progress: Math.min(1, Math.max(0, progress))}
}

// Two contexts with one identity share music: ports by palette, voyages by
// their pair of origin and destination palettes.
export function identity(manifest, context) {
  if (!context) return null
  if (context.kind === 'port') {
    const palette = paletteOf(manifest, context.port)
    return palette && `port:${palette}`
  }
  const origin = paletteOf(manifest, context.origin)
  const destination = paletteOf(manifest, context.destination)
  return origin && destination ? `voyage:${origin}>${destination}` : null
}

// A voyage draws from the destination palette with probability equal to its
// progress, and avoids repeating the previous piece when the pool allows.
export function choosePiece(manifest, context, previous, random = Math.random) {
  if (!identity(manifest, context)) return null
  const id = context.kind === 'port' ? paletteOf(manifest, context.port)
    : random() < context.progress ? paletteOf(manifest, context.destination) : paletteOf(manifest, context.origin)
  const pool = manifest.palettes.find(palette => palette.id === id)[context.kind === 'port' ? 'port' : 'voyage']
  const candidates = pool.length > 1 ? pool.filter(slug => slug !== previous) : pool
  return candidates[Math.floor(random() * candidates.length)]
}
```

- [ ] **Step 3: Run, break, commit**

Run the test → PASS. Change `random() < context.progress` to `<=` and confirm
the progress-0 case fails; restore. Run `npm run desktop:test`.

```bash
git add assets/js/music_policy.js test/desktop/music-policy.test.mjs
git commit -m "Add background music piece policy

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 10: Audio engine

**Files:**
- Create: `assets/js/music_engine.js`
- Create: `test/desktop/music-engine.test.mjs`

**Interfaces:**
- Produces:
  - `volumeGain(value) -> number`, `envelopeAt(envelope, t)`, `fadeCurve(envelope) -> Float32Array`, `trackUrl(baseUrl, track)`
  - `createEngine({context, createAudio, baseUrl, timeoutMs = 10000, setTimer, clearTimer}) -> {prepare(track, offset) -> Promise<Voice>, setVolume(v), unlock() -> Promise}`
  - `Voice`: `{track, position, duration, play() -> Promise, pause(), fade('in'|'out', seconds), gain(), onProgress(fn), onEnded(fn), dispose()}`
  - Envelope: `{kind: 'hold', value}` or `{kind: 'in'|'out', from, start, duration}`.

- [ ] **Step 1: Failing tests**

```js
import {test} from 'node:test'
import assert from 'node:assert/strict'
import {readFileSync} from 'node:fs'
const source = readFileSync(new URL('../../assets/js/music_engine.js', import.meta.url), 'utf8')
const engineModule = await import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`)
const {volumeGain, envelopeAt, fadeCurve, trackUrl, createEngine} = engineModule
const flush = () => new Promise(resolve => setImmediate(resolve))
const close = (a, b) => assert.ok(Math.abs(a - b) < 1e-6, `${a} ≈ ${b}`)

function param() {
  const p = {value: 0, calls: []}
  for (const name of ['cancelScheduledValues', 'setValueAtTime', 'setValueCurveAtTime', 'linearRampToValueAtTime'])
    p[name] = (...args) => p.calls.push([name, ...args])
  return p
}
function fakeContext() {
  const context = {currentTime: 0, destination: {}, gains: [], resumed: 0,
    createGain() { const node = {gain: param(), connect() {}, disconnect() { node.disconnected = true }}; context.gains.push(node); return node },
    createMediaElementSource: element => ({element, connect() {}, disconnect() {}}),
    resume() { context.resumed++; return Promise.resolve() }}
  return context
}
function fakeAudio() {
  const listeners = new Map()
  const audio = {currentTime: 0, duration: 120, paused: true, attributes: {}, playResult: Promise.resolve(),
    addEventListener(type, fn) { listeners.set(type, [...(listeners.get(type) ?? []), fn]) },
    removeEventListener() {},
    dispatch(type) { const fns = listeners.get(type) ?? []; listeners.set(type, []); fns.forEach(fn => fn()) },
    set src(value) { audio.attributes.src = value }, get src() { return audio.attributes.src },
    removeAttribute(name) { delete audio.attributes[name] }, load() { audio.loads = (audio.loads ?? 0) + 1 },
    play() { audio.paused = false; return audio.playResult }, pause() { audio.paused = true }}
  return audio
}
function timers() {
  const pending = []
  return {pending, setTimer: (fn, ms) => { const h = {fn, ms}; pending.push(h); return h },
    clearTimer: h => { const i = pending.indexOf(h); if (i >= 0) pending.splice(i, 1) },
    fire() { pending.splice(0).forEach(h => h.fn()) }}
}
const track = {file: 'a.ogg', output_sha256: '0123456789abcdef', title: 'A', artists: ['X']}

test('volume maps to the square of the slider fraction', () => {
  assert.equal(volumeGain(0), 0)
  close(volumeGain(30), 0.09)
  assert.equal(volumeGain(100), 1)
  assert.equal(volumeGain(140), 1)
  assert.equal(volumeGain(-5), 0)
})

test('fades follow cosine out from the current gain and sine in', () => {
  const out = {kind: 'out', from: 0.8, start: 10, duration: 5}
  close(envelopeAt(out, 10), 0.8)
  close(envelopeAt(out, 12.5), 0.8 * Math.cos(Math.PI / 4))
  close(envelopeAt(out, 15), 0)
  const fadeIn = {kind: 'in', from: 0, start: 3, duration: 2}
  close(envelopeAt(fadeIn, 4), Math.sin(Math.PI / 4))
  close(envelopeAt(fadeIn, 9), 1)
  const curve = fadeCurve(fadeIn)
  assert.equal(curve.length, 201)
  close(curve[0], 0)
  close(curve[100], Math.sin(Math.PI / 4))
  close(curve[200], 1)
})

test('track URLs are versioned by output hash', () => {
  assert.equal(trackUrl('https://h.test/audio/', track), 'https://h.test/audio/a.ogg?v=0123456789ab')
})

test('prepare seeks to the entry before resolving and schedules exact curves', async () => {
  const context = fakeContext(), audio = fakeAudio(), clock = timers()
  const engine = createEngine({context, createAudio: () => audio, baseUrl: 'https://h.test/audio/', ...clock})
  let voice
  engine.prepare(track, 7.5).then(v => { voice = v })
  audio.dispatch('loadedmetadata')
  assert.equal(audio.currentTime, 7.5)
  await flush()
  assert.equal(voice, undefined)
  audio.dispatch('seeked')
  await flush()
  assert.equal(voice.track, track)
  const gain = context.gains[1].gain
  context.currentTime = 2
  voice.fade('in', 2)
  const [, , [, curve, start, duration]] = gain.calls
  assert.deepEqual(gain.calls[0], ['cancelScheduledValues', 0])
  assert.deepEqual(gain.calls[1], ['setValueAtTime', 0, 2])
  close(start, 2.01)
  assert.equal(duration, 2)
  close(curve[0], 0)
  context.currentTime = 3.01
  close(voice.gain(), Math.sin(Math.PI / 4))
  voice.fade('out', 5)
  const last = gain.calls.at(-1)
  close(last[1][0], Math.sin(Math.PI / 4))
  close(last[1].at(-1), 0)
})

test('load errors and timeouts reject and dispose the element', async () => {
  const context = fakeContext(), clock = timers()
  const failing = fakeAudio()
  const engine = createEngine({context, createAudio: () => failing, baseUrl: 'https://h.test/', ...clock})
  const rejected = engine.prepare(track, 0)
  failing.dispatch('error')
  await assert.rejects(rejected)
  assert.equal(failing.src, undefined)
  const slow = fakeAudio()
  const engine2 = createEngine({context, createAudio: () => slow, baseUrl: 'https://h.test/', ...clock})
  const timedOut = engine2.prepare(track, 0)
  clock.fire()
  await assert.rejects(timedOut, /loading timed out/)
})

test('play times out separately from loading', async () => {
  const context = fakeContext(), audio = fakeAudio(), clock = timers()
  audio.playResult = new Promise(() => {})
  const engine = createEngine({context, createAudio: () => audio, baseUrl: 'https://h.test/', ...clock})
  const ready = engine.prepare(track, 0)
  audio.dispatch('loadedmetadata'); audio.dispatch('canplay')
  const voice = await ready
  assert.equal(clock.pending.length, 0)
  const playing = voice.play()
  await flush()
  clock.fire()
  await assert.rejects(playing, /playback timed out/)
})

test('volume ramps over 50 ms and unlock resumes the context', async () => {
  const context = fakeContext(), clock = timers()
  const engine = createEngine({context, createAudio: fakeAudio, baseUrl: 'https://h.test/', ...clock})
  context.currentTime = 1
  engine.setVolume(30)
  const master = context.gains[0].gain
  const ramp = master.calls.at(-1)
  assert.equal(ramp[0], 'linearRampToValueAtTime')
  close(ramp[1], 0.09)
  close(ramp[2], 1.05)
  await engine.unlock()
  assert.equal(context.resumed, 1)
})
```

Run: `node --test test/desktop/music-engine.test.mjs` → FAIL.

- [ ] **Step 2: Implement**

`assets/js/music_engine.js`:

```js
// Streams each piece through an <audio> element routed into Web Audio, so the
// file downloads progressively while fades follow exact gain curves.

export const volumeGain = value => (Math.min(100, Math.max(0, Number(value) || 0)) / 100) ** 2

// Fade-out: from * cos(pi*p/2). Fade-in: from + (1 - from) * sin(pi*p/2).
export function envelopeAt(envelope, t) {
  if (envelope.kind === 'hold') return envelope.value
  const p = envelope.duration > 0 ? Math.min(1, Math.max(0, (t - envelope.start) / envelope.duration)) : 1
  return envelope.kind === 'in'
    ? envelope.from + (1 - envelope.from) * Math.sin(Math.PI * p / 2)
    : envelope.from * Math.cos(Math.PI * p / 2)
}

export function fadeCurve(envelope) {
  const samples = Math.max(2, Math.ceil(envelope.duration * 100) + 1)
  return Float32Array.from({length: samples}, (_, i) =>
    envelopeAt(envelope, envelope.start + envelope.duration * i / (samples - 1)))
}

export const trackUrl = (baseUrl, track) =>
  new URL(`${track.file}?v=${track.output_sha256.slice(0, 12)}`, baseUrl).href

// A curve may not overlap the value set just before it.
const LEAD = 0.01

export function createEngine({context, createAudio, baseUrl, timeoutMs = 10_000,
  setTimer = (fn, ms) => setTimeout(fn, ms), clearTimer = handle => clearTimeout(handle)}) {
  const master = context.createGain()
  master.gain.value = 0
  master.connect(context.destination)

  const timed = (promise, label) => new Promise((resolve, reject) => {
    const timer = setTimer(() => reject(new Error(`${label} timed out`)), timeoutMs)
    promise.then(value => { clearTimer(timer); resolve(value) }, error => { clearTimer(timer); reject(error) })
  })

  function createVoice(track) {
    const element = createAudio()
    element.preload = 'auto'
    const source = context.createMediaElementSource(element)
    const gain = context.createGain()
    gain.gain.value = 0
    source.connect(gain)
    gain.connect(master)
    let disposed = false
    const voice = {
      element,
      track,
      envelope: {kind: 'hold', value: 0},
      get position() { return element.currentTime },
      get duration() { return element.duration },
      play: () => timed(Promise.resolve().then(() => element.play()), 'playback'),
      pause() { if (!disposed) element.pause() },
      gain: () => envelopeAt(voice.envelope, context.currentTime),
      fade(kind, duration) {
        const now = context.currentTime
        const from = envelopeAt(voice.envelope, now)
        voice.envelope = {kind, from, start: now + LEAD, duration}
        gain.gain.cancelScheduledValues(0)
        gain.gain.setValueAtTime(from, now)
        gain.gain.setValueCurveAtTime(fadeCurve(voice.envelope), now + LEAD, duration)
      },
      onProgress: fn => element.addEventListener('timeupdate', () => fn()),
      onEnded: fn => element.addEventListener('ended', () => fn()),
      dispose() {
        if (disposed) return
        disposed = true
        element.pause()
        element.removeAttribute('src')
        element.load()
        source.disconnect()
        gain.disconnect()
      },
    }
    return voice
  }

  // Resolves once the element can play from `offset` (seconds in the encoded file).
  function prepare(track, offset = 0) {
    const voice = createVoice(track)
    const {element} = voice
    const loaded = new Promise((resolve, reject) => {
      element.addEventListener('error', () => reject(element.error ?? new Error('audio failed to load')), {once: true})
      element.addEventListener('loadedmetadata', () => {
        element.addEventListener(offset > 0 ? 'seeked' : 'canplay', () => resolve(voice), {once: true})
        if (offset > 0) element.currentTime = offset
      }, {once: true})
    })
    element.src = trackUrl(baseUrl, track)
    element.load()
    return timed(loaded, 'loading').catch(error => { voice.dispose(); throw error })
  }

  function setVolume(value) {
    const now = context.currentTime
    const param = master.gain
    param.cancelScheduledValues(0)
    param.setValueAtTime(param.value, now)
    param.linearRampToValueAtTime(volumeGain(value), now + 0.05)
  }

  return {prepare, setVolume, unlock: () => context.resume()}
}
```

- [ ] **Step 3: Run, break, commit**

Run the test → PASS. Swap `cos` and `sin` in `envelopeAt`; confirm the fade
test fails; restore. Run `npm run desktop:test`.

```bash
git add assets/js/music_engine.js test/desktop/music-engine.test.mjs
git commit -m "Add the streamed Web Audio music engine

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 11: Transition director

**Files:**
- Create: `assets/js/music_transitions.js`
- Create: `test/desktop/music-transitions.test.mjs`

**Interfaces:**
- Consumes: Voice API (Task 10); `identity`, `choosePiece` (Task 9) injected
  as `policy`.
- Produces: `TIMING`; `createDirector({manifest, engine, policy, now, setTimer, clearTimer, random, onStart})`
  returning `{setContext(context), setEnabled(boolean), setForeground(boolean), unlock(), destroy()}`.
  `now()` returns seconds. `onStart(track, slug)` fires only after a piece's
  `play()` fulfils and its fade-in begins.

- [ ] **Step 1: Failing tests**

`test/desktop/music-transitions.test.mjs`:

```js
import {test} from 'node:test'
import assert from 'node:assert/strict'
import {readFileSync} from 'node:fs'
const load = name => import(`data:text/javascript;base64,${Buffer.from(
  readFileSync(new URL(`../../assets/js/${name}.js`, import.meta.url), 'utf8')).toString('base64')}`)
const {createDirector} = await load('music_transitions')
const {identity, choosePiece} = await load('music_policy')
const flush = () => new Promise(resolve => setImmediate(resolve))

const track = (slug, entry = 0) => ({file: `${slug}.ogg`, title: slug, artists: ['X'], duration_s: 120, entry_s: entry})
const manifest = {
  palettes: [
    {id: 'east', ports: ['Shanghai', 'Busan'], port: ['east-port'], voyage: ['east-voyage']},
    {id: 'west', ports: ['Tangier', 'Valencia'], port: ['west-a', 'west-b'], voyage: ['west-voyage']},
  ],
  tracks: {'east-port': track('east-port'), 'east-voyage': track('east-voyage', 16),
    'west-a': track('west-a', 2), 'west-b': track('west-b'), 'west-voyage': track('west-voyage', 8)},
}
const port = p => ({kind: 'port', port: p})
const voyage = (origin, destination, progress) => ({kind: 'voyage', ship: 's', origin, destination, progress})

function harness() {
  let t = 0
  const timers = []
  const prepared = []
  const starts = []
  const clock = {
    now: () => t,
    setTimer: (fn, ms) => { const h = {at: t + ms / 1000, fn}; timers.push(h); return h },
    clearTimer: h => { const i = timers.indexOf(h); if (i >= 0) timers.splice(i, 1) },
  }
  const voiceFor = (trackValue, offset) => {
    // Media time advances with the elapsed clock only while playback runs.
    let position = offset, playingAt = null
    const voice = {track: trackValue, offset, fades: [], plays: [], duration: 120,
      disposed: false, paused: false, progressFns: [], endedFns: [],
      play() { return new Promise((resolve, reject) => voice.plays.push({at: t,
        resolve() { position = voice.position; playingAt = t; voice.paused = false; resolve() }, reject})) },
      get position() { return position + (playingAt === null ? 0 : t - playingAt) },
      set position(value) { position = value; if (playingAt !== null) playingAt = t },
      pause() { position = voice.position; playingAt = null; voice.paused = true },
      fade(kind, duration) { voice.fades.push([kind, t, duration]) },
      onProgress(fn) { voice.progressFns.push(fn) }, onEnded(fn) { voice.endedFns.push(fn) },
      progress(position) { voice.position = position; voice.progressFns.forEach(fn => fn()) },
      end() { voice.pause(); voice.endedFns.forEach(fn => fn()) },
      dispose() { voice.pause(); voice.disposed = true }}
    return voice
  }
  const engine = {
    prepare(trackValue, offset) {
      return new Promise((resolve, reject) => {
        const voice = voiceFor(trackValue, offset)
        prepared.push({track: trackValue, offset, voice, at: t,
          resolve: async () => { resolve(voice); await flush() },
          reject: async () => { reject(new Error('load')); await flush() }})
      })
    },
  }
  const director = createDirector({manifest, engine, policy: {identity, choosePiece}, ...clock,
    random: () => 0, onStart: (trackValue, slug) => starts.push([slug, t])})
  const advance = async to => {
    for (;;) {
      timers.sort((a, b) => a.at - b.at)
      const next = timers[0]
      if (!next || next.at > to + 1e-9) break
      timers.shift()
      t = next.at
      next.fn()
      await flush()
    }
    t = to
    await flush()
  }
  return {director, prepared, starts, advance, last: () => prepared.at(-1)}
}

// Starts east-port playing at t = 0 and returns its voice.
async function playing(h, context = port('Shanghai')) {
  h.director.setContext(context)
  h.director.unlock()
  await h.last().resolve()
  const voice = h.last().voice
  voice.plays[0].resolve()
  await flush()
  return voice
}

test('a stable selection fades out over 0–5 s and in over 3–5 s', async () => {
  const h = harness()
  const east = await playing(h)
  assert.deepEqual(east.fades, [['in', 0, 2]])
  await h.advance(10)
  h.director.setContext(port('Tangier'))
  assert.deepEqual(east.fades.at(-1), ['out', 10, 5])
  assert.equal(h.last().offset, 2)
  await h.last().resolve()
  const west = h.last().voice
  await h.advance(12.99)
  assert.equal(west.plays.length, 0)
  await h.advance(13)
  assert.equal(west.plays[0].at, 13)
  assert.deepEqual(h.starts.at(-1), ['east-port', 0])
  west.plays[0].resolve(); await flush()
  assert.deepEqual(west.fades, [['in', 13, 2]])
  assert.deepEqual(h.starts.at(-1), ['west-a', 13])
  await h.advance(15)
  assert.ok(east.paused && east.disposed)
})

test('a reselection at 2 s is silent at 5 s and fades in from 6 to 8 s', async () => {
  const h = harness()
  const east = await playing(h)
  await h.advance(10)
  h.director.setContext(port('Tangier'))
  const westPending = h.last()
  await h.advance(12)
  h.director.setContext(voyage('Busan', 'Tangier', 0))
  await westPending.resolve()
  assert.ok(westPending.voice.disposed)
  assert.equal(h.last().offset, 16)
  await h.last().resolve()
  const next = h.last().voice
  await h.advance(15.99)
  assert.equal(next.plays.length, 0)
  assert.equal(east.fades.filter(([kind]) => kind === 'out').length, 1)
  await h.advance(16)
  next.plays[0].resolve(); await flush()
  assert.deepEqual(next.fades, [['in', 16, 2]])
})

test('a change while silent restarts the three-second wait even when ready', async () => {
  const h = harness()
  await playing(h)
  await h.advance(10)
  h.director.setContext(port('Tangier'))
  await h.advance(11)
  h.director.setContext(voyage('Busan', 'Tangier', 0))
  await h.last().resolve()
  await h.advance(15.5)
  h.director.setContext(port('Busan'))
  await h.last().resolve()
  const latest = h.last().voice
  await h.advance(18.49)
  assert.equal(latest.plays.length, 0)
  await h.advance(18.5)
  assert.equal(latest.plays[0].at, 18.5)
})

test('a change during a fade-in fades all audible music from current gains', async () => {
  const h = harness()
  const east = await playing(h)
  await h.advance(10)
  h.director.setContext(port('Tangier'))
  await h.last().resolve()
  await h.advance(13)
  const west = h.last().voice
  west.plays[0].resolve(); await flush()
  await h.advance(14)
  h.director.setContext(voyage('Busan', 'Tangier', 0))
  assert.deepEqual(east.fades.at(-1), ['out', 14, 5])
  assert.deepEqual(west.fades.at(-1), ['out', 14, 5])
  await h.last().resolve()
  await h.advance(16.99)
  assert.equal(h.last().voice.plays.length, 0)
  await h.advance(17)
  assert.equal(h.last().voice.plays.length, 1)
})

test('an unchanged identity changes nothing, including pending transitions', async () => {
  const h = harness()
  const east = await playing(h)
  h.director.setContext(port('Busan'))
  assert.equal(h.prepared.length, 1)
  assert.deepEqual(east.fades, [['in', 0, 2]])
  await h.advance(10)
  h.director.setContext(port('Tangier'))
  await h.last().resolve()
  await h.advance(11)
  h.director.setContext(port('Valencia'))
  assert.equal(h.prepared.length, 2)
  await h.advance(13)
  assert.equal(h.last().voice.plays[0].at, 13)
})

test('progress updates within a voyage change nothing', async () => {
  const h = harness()
  const voice = await playing(h, voyage('Busan', 'Tangier', 0.2))
  h.director.setContext(voyage('Shanghai', 'Valencia', 0.3))
  h.director.setContext(voyage('Busan', 'Tangier', 0.9))
  assert.equal(h.prepared.length, 1)
  assert.deepEqual(voice.fades, [['in', 0, 2]])
})

test('late audio gets a full fade from its actual start and no early credit', async () => {
  const h = harness()
  await playing(h)
  await h.advance(10)
  h.director.setContext(port('Tangier'))
  await h.advance(14.5)
  await h.last().resolve()
  const west = h.last().voice
  assert.equal(west.plays[0].at, 14.5)
  assert.equal(h.starts.length, 1)
  await h.advance(15.2)
  west.plays[0].resolve(); await flush()
  assert.deepEqual(west.fades, [['in', 15.2, 2]])
  assert.deepEqual(h.starts.at(-1), ['west-a', 15.2])
})

test('a superseded play() is paused and disposed without fade or credit', async () => {
  const h = harness()
  await playing(h)
  await h.advance(10)
  h.director.setContext(port('Tangier'))
  await h.last().resolve()
  await h.advance(13)
  const west = h.last().voice
  await h.advance(13.5)
  h.director.setContext(voyage('Busan', 'Tangier', 0))
  west.plays[0].resolve(); await flush()
  assert.ok(west.paused && west.disposed)
  assert.deepEqual(west.fades, [])
  assert.equal(h.starts.length, 1)
})

test('selection just before track end preserves its deadline and suppresses automatic starts', async () => {
  const h = harness()
  const east = await playing(h)
  await h.advance(10)
  east.position = 119
  h.director.setContext(port('Tangier'))
  await h.last().resolve()
  const count = h.prepared.length
  east.progress(119.5)
  await h.advance(11)
  east.end()
  assert.ok(east.disposed)
  assert.equal(h.prepared.length, count)
  await h.advance(13)
  assert.equal(h.last().voice.plays[0].at, 13)
})

test('pieces are prepared ten seconds before the end and crossfade over the last two', async () => {
  const h = harness()
  const a = await playing(h, port('Tangier'))
  await h.advance(100)
  a.progress(111)
  assert.equal(h.prepared.length, 2)
  assert.equal(h.last().track, manifest.tracks['west-b'])
  assert.equal(h.last().offset, 0)
  await h.last().resolve()
  const b = h.last().voice
  assert.equal(b.plays.length, 0)
  await h.advance(107)
  assert.equal(b.plays[0].at, 107)
  b.plays[0].resolve(); await flush()
  assert.deepEqual(a.fades.at(-1), ['out', 107, 2])
  assert.deepEqual(b.fades, [['in', 107, 2]])
  assert.deepEqual(h.starts.at(-1), ['west-b', 107])
})

test('a selection during an automatic crossfade fades both pieces', async () => {
  const h = harness()
  const a = await playing(h, port('Tangier'))
  a.progress(118)
  await h.last().resolve()
  const b = h.last().voice
  b.plays[0].resolve(); await flush()
  await h.advance(1)
  h.director.setContext(port('Shanghai'))
  assert.deepEqual(a.fades.at(-1), ['out', 1, 5])
  assert.deepEqual(b.fades.at(-1), ['out', 1, 5])
})

test('turning off cancels every pending start; context changes while off cannot play', async () => {
  const h = harness()
  const east = await playing(h)
  await h.advance(10)
  h.director.setContext(port('Tangier'))
  const west = h.last()
  await h.advance(11)
  h.director.setEnabled(false)
  assert.deepEqual(east.fades.at(-1), ['out', 11, 1])
  await west.resolve()
  assert.ok(west.voice.disposed)
  h.director.setContext(voyage('Busan', 'Tangier', 0))
  await h.advance(20)
  assert.equal(h.prepared.length, 2)
  h.director.setEnabled(true)
  assert.equal(h.last().offset, 16)
  await h.last().resolve()
  assert.equal(h.last().voice.plays[0].at, 20)
})

test('turning off during an automatic crossfade fades both and starts nothing', async () => {
  const h = harness()
  const a = await playing(h, port('Tangier'))
  a.progress(118)
  await h.last().resolve()
  const b = h.last().voice
  b.plays[0].resolve(); await flush()
  h.director.setEnabled(false)
  assert.deepEqual(a.fades.at(-1), ['out', 0, 1])
  assert.deepEqual(b.fades.at(-1), ['out', 0, 1])
  await h.advance(5)
  assert.ok(a.disposed && b.disposed)
})

test('toggling back on during the off-fade starts one fresh piece', async () => {
  const h = harness()
  const east = await playing(h)
  await h.advance(10)
  h.director.setEnabled(false)
  await h.advance(10.5)
  h.director.setEnabled(true)
  await h.last().resolve()
  const fresh = h.last().voice
  assert.notEqual(fresh, east)
  fresh.plays[0].resolve(); await flush()
  await h.advance(11)
  assert.ok(east.disposed)
  assert.equal(h.prepared.length, 2)
})

test('switching away pauses port music for resume and repicks voyages', async () => {
  const h = harness()
  const port1 = await playing(h, port('Tangier'))
  await h.advance(20)
  h.director.setForeground(false)
  assert.deepEqual(port1.fades.at(-1), ['out', 20, 1])
  await h.advance(21)
  assert.ok(port1.paused && !port1.disposed)
  await h.advance(30)
  h.director.setForeground(true)
  assert.equal(h.prepared.length, 1)
  assert.equal(port1.plays.length, 2)
  port1.plays[1].resolve(); await flush()
  assert.deepEqual(port1.fades.at(-1), ['in', 30, 2])
  assert.deepEqual(h.starts.at(-1), ['west-a', 30])

  const v = harness()
  const sailing = await playing(v, voyage('Busan', 'Tangier', 0))
  v.director.setForeground(false)
  await v.advance(2)
  assert.ok(sailing.disposed)
  v.director.setForeground(true)
  assert.equal(v.prepared.length, 2)
  assert.equal(v.last().offset, 16)
})

test('switching away during a port crossfade resumes the incoming port piece', async () => {
  const h = harness()
  const a = await playing(h, port('Tangier'))
  a.progress(118)
  await h.last().resolve()
  const b = h.last().voice
  b.plays[0].resolve(); await flush()
  await h.advance(1)
  b.position = 42
  h.director.setForeground(false)
  await h.advance(2)
  assert.ok(a.disposed && b.paused && !b.disposed)
  const position = b.position
  assert.equal(position, 43)
  await h.advance(4)
  h.director.setForeground(true)
  assert.equal(h.prepared.length, 2)
  assert.equal(b.plays.length, 2)
  b.plays[1].resolve(); await flush()
  assert.equal(b.position, position)
  assert.deepEqual(b.fades.at(-1), ['in', 4, 2])
  assert.deepEqual(h.starts.at(-1), ['west-b', 4])
})

test('switching away during a selection overlap resumes the current port piece', async () => {
  const h = harness()
  const a = await playing(h)
  await h.advance(10)
  h.director.setContext(port('Tangier'))
  await h.last().resolve()
  await h.advance(13)
  const b = h.last().voice
  b.plays[0].resolve(); await flush()
  await h.advance(14)
  h.director.setForeground(false)
  await h.advance(15)
  assert.ok(a.disposed && b.paused && !b.disposed)
  const position = b.position
  await h.advance(20)
  h.director.setForeground(true)
  assert.equal(h.prepared.length, 2)
  assert.equal(b.plays.length, 2)
  b.plays[1].resolve(); await flush()
  assert.equal(b.position, position)
})

test('waits for foreground before starting', async () => {
  const h = harness()
  h.director.setForeground(false)
  h.director.setContext(port('Shanghai'))
  h.director.unlock()
  assert.equal(h.prepared.length, 0)
  h.director.setForeground(true)
  assert.equal(h.prepared.length, 1)
})

test('nothing starts before the first gesture unlocks audio', async () => {
  const h = harness()
  h.director.setContext(port('Shanghai'))
  await h.advance(30)
  assert.equal(h.prepared.length, 0)
  h.director.unlock()
  assert.equal(h.prepared.length, 1)
})

test('an unknown port fades to silence without a pending piece', async () => {
  const h = harness()
  const east = await playing(h)
  await h.advance(10)
  h.director.setContext(port('Atlantis'))
  assert.deepEqual(east.fades.at(-1), ['out', 10, 5])
  assert.equal(h.prepared.length, 1)
  await h.advance(30)
  assert.equal(h.starts.length, 1)
})

test('three consecutive failures stop music until the identity changes', async () => {
  const h = harness()
  h.director.setContext(port('Tangier'))
  h.director.unlock()
  await h.last().reject()
  await h.last().reject()
  await h.last().reject()
  assert.equal(h.prepared.length, 3)
  await h.advance(30)
  assert.equal(h.prepared.length, 3)
  h.director.setForeground(false)
  h.director.setEnabled(false)
  h.director.setContext(port('Valencia')) // unchanged palette cannot clear the lock
  h.director.setEnabled(true)
  h.director.setForeground(true)
  h.director.unlock()
  assert.equal(h.prepared.length, 3)
  assert.equal(h.starts.length, 0)
  h.director.setContext(port('Shanghai'))
  assert.equal(h.prepared.length, 4)
})

test('automatic failures stop audible music and cannot retry on progress or focus', async () => {
  const h = harness()
  const a = await playing(h)
  a.progress(111)
  await h.last().reject()
  await h.last().reject()
  await h.last().reject()
  assert.equal(h.prepared.length, 4) // current piece and three failed candidates
  assert.deepEqual(a.fades.at(-1), ['out', 0, 1])
  a.progress(112)
  await h.advance(1)
  assert.ok(a.paused && a.disposed)
  h.director.setForeground(false)
  h.director.setForeground(true)
  h.director.setEnabled(false)
  h.director.setEnabled(true)
  assert.equal(h.prepared.length, 4)
  assert.equal(h.starts.length, 1)
  h.director.setContext(port('Tangier'))
  assert.equal(h.prepared.length, 5)
})

test('an identity change while disabled or away releases the failure lock', async () => {
  for (const setting of ['setEnabled', 'setForeground']) {
    const h = harness()
    h.director.setContext(port('Tangier'))
    h.director.unlock()
    await h.last().reject()
    await h.last().reject()
    await h.last().reject()
    h.director[setting](false)
    h.director.setContext(port('Shanghai'))
    assert.equal(h.prepared.length, 3)
    h.director[setting](true)
    assert.equal(h.prepared.length, 4)
    await h.last().resolve()
    h.last().voice.plays[0].resolve(); await flush()
    assert.deepEqual(h.starts, [['east-port', 0]])
  }
})

test('a rejected play counts as a failure and is replaced', async () => {
  const h = harness()
  h.director.setContext(port('Tangier'))
  h.director.unlock()
  await h.last().resolve()
  h.last().voice.plays[0].reject(new Error('blocked')); await flush()
  assert.equal(h.prepared.length, 2)
  assert.equal(h.last().track, manifest.tracks['west-b'])
})

test('destroy disposes everything and ignores late callbacks', async () => {
  const h = harness()
  const east = await playing(h)
  h.director.setContext(port('Tangier'))
  const pending = h.last()
  h.director.destroy()
  assert.ok(east.disposed)
  await pending.resolve()
  assert.ok(pending.voice.disposed)
})
```

Run: `node --test test/desktop/music-transitions.test.mjs` → FAIL.

- [ ] **Step 2: Implement**

`assets/js/music_transitions.js`:

```js
// Owns every change in what is audible: selection transitions, automatic
// crossfades between pieces, silent waits, disabling, hiding and resuming.
// Timing follows DESIGN.md's Background music section. Every asynchronous
// result is checked against the current generation and pending piece, so a
// superseded load or play never becomes audible or earns a credit.

export const TIMING = {settle: 3, fadeOut: 5, fadeIn: 2, silence: 1, crossfade: 2, prepareAhead: 10, quickFade: 1}
const MAX_FAILURES = 3

export function createDirector({manifest, engine, policy, now, setTimer, clearTimer,
  random = Math.random, onStart = () => {}}) {
  let desired = {context: null, id: null}
  let enabled = true, foreground = true, unlocked = false, destroyed = false
  let generation = 0
  let mode = 'idle'            // idle: may start at once; playing; stopped after failures
  let current = null           // {voice, id, slug}
  const voices = new Set()     // voices whose gain may be above zero
  let transition = null        // {outgoingEndsAt, deadline}
  let pending = null           // the one incoming piece
  let paused = null            // {voice, id, slug} kept while away
  let failures = 0
  let failureLocked = false    // cleared only by a musical identity change
  let wake = null

  const remaining = voice => {
    const left = voice.duration - voice.position
    return Number.isFinite(left) ? left : Infinity
  }

  function retire(voice, seconds, keep = false) {
    voice.role = 'outgoing'
    voice.fade('out', seconds)
    const token = voice.retiring = {}
    setTimer(() => {
      if (voice.retiring !== token) return
      voices.delete(voice)
      voice.pause()
      if (!keep) voice.dispose()
    }, seconds * 1000)
  }

  function choose(context, previous, automatic) {
    const slug = policy.choosePiece(manifest, context, previous, random)
    if (!slug) return null
    const track = manifest.tracks[slug]
    return {id: policy.identity(manifest, context), context, slug, track, automatic,
      offset: automatic ? 0 : track.entry_s ?? 0, voice: null, ready: false, starting: false, notBefore: now()}
  }

  function discardPending() {
    if (pending?.voice && !pending.starting) pending.voice.dispose()
    pending = null
  }

  function prepare(next) {
    if (destroyed || failureLocked) { next?.voice?.dispose(); return }
    pending = next
    if (!next) return
    if (next.ready) { pump(); return }
    engine.prepare(next.track, next.offset).then(voice => {
      if (pending !== next || destroyed) { voice.dispose(); return }
      next.voice = voice
      next.ready = true
      pump()
    }, () => { if (pending === next) fail(next) })
  }

  function fail(failed) {
    failed.voice?.dispose()
    pending = null
    failures += 1
    if (failures >= MAX_FAILURES) {
      failureLocked = true
      silence(TIMING.quickFade, false)
      mode = 'stopped'
      return
    }
    const next = choose(failed.context, failed.slug, failed.automatic)
    if (next) next.notBefore = failed.notBefore
    prepare(next)
  }

  function pump() {
    if (wake) { clearTimer(wake); wake = null }
    if (destroyed || failureLocked || !enabled || !foreground || !unlocked) return
    if (!pending?.ready || pending.starting) return
    const t = now()
    const due = transition ? transition.deadline
      : pending.automatic && current ? t + Math.max(0, remaining(current.voice) - TIMING.crossfade)
      : pending.notBefore
    if (due > t) { wake = setTimer(() => { wake = null; pump() }, (due - t) * 1000); return }
    start(pending)
  }

  function start(next) {
    next.starting = true
    const voice = next.voice
    const gen = generation
    voice.play().then(() => {
      if (gen !== generation || pending !== next || destroyed) { voice.pause(); voice.dispose(); return }
      pending = null
      transition = null
      failures = 0
      mode = 'playing'
      if (next.automatic && current && current.voice !== voice) retire(current.voice, TIMING.crossfade)
      voice.retiring = null
      voice.role = 'current'
      voices.add(voice)
      voice.fade('in', TIMING.fadeIn)
      current = {voice, id: next.id, slug: next.slug}
      watch(voice)
      onStart(next.track, next.slug)
    }, () => { if (gen === generation && pending === next) fail(next) })
  }

  function watch(voice) {
    if (voice.watched) return
    voice.watched = true
    voice.onProgress(() => {
      if (current?.voice !== voice || transition || failureLocked || !enabled || !foreground) return
      if (!pending && remaining(voice) <= TIMING.prepareAhead) prepare(choose(desired.context, current.slug, true))
      pump()
    })
    voice.onEnded(() => {
      voices.delete(voice)
      voice.dispose()
      if (current?.voice === voice) { current = null; pump() }
    })
  }

  function select() {
    const t = now()
    generation += 1
    failures = 0
    discardPending()
    const incoming = [...voices].some(voice => voice.role !== 'outgoing')
    if (incoming) {
      for (const voice of [...voices]) retire(voice, TIMING.fadeOut)
      transition = {outgoingEndsAt: t + TIMING.fadeOut, deadline: t + TIMING.settle}
    } else if (transition && t < transition.outgoingEndsAt) {
      transition.deadline = transition.outgoingEndsAt + TIMING.silence
    } else if (transition || mode !== 'idle') {
      transition = {outgoingEndsAt: transition?.outgoingEndsAt ?? t, deadline: t + TIMING.settle}
    }
    current = null
    if (mode === 'stopped') mode = 'playing'
    prepare(desired.id ? choose(desired.context, null, false) : null)
  }

  // Keep the current port piece even if an outgoing voice still overlaps it.
  function silence(seconds, keepPort) {
    generation += 1
    if (wake) { clearTimer(wake); wake = null }
    discardPending()
    transition = null
    const kept = keepPort && !failureLocked && current?.id?.startsWith('port:') ? current : null
    for (const voice of [...voices]) retire(voice, seconds, voice === kept?.voice)
    current = null
    mode = 'idle'
    if (paused && paused.voice !== kept?.voice) paused.voice.dispose()
    paused = kept
  }

  function begin() {
    if (destroyed || failureLocked || !enabled || !foreground || !unlocked || !desired.id || pending) return
    generation += 1
    if (paused && paused.id === desired.id) {
      const {voice, id, slug} = paused
      paused = null
      prepare({id, context: desired.context, slug, track: voice.track, automatic: false, offset: 0,
        voice, ready: true, starting: false, notBefore: now()})
      return
    }
    paused?.voice.dispose()
    paused = null
    prepare(choose(desired.context, null, false))
  }

  return {
    setContext(context) {
      const id = policy.identity(manifest, context)
      const changed = id !== desired.id
      desired = {context, id}
      if (changed) { failureLocked = false; failures = 0 }
      if (!changed || destroyed || !enabled || !foreground || !unlocked) return
      if (mode === 'idle' && voices.size === 0 && !transition) { discardPending(); begin(); return }
      select()
    },
    setEnabled(on) {
      if (on === enabled || destroyed) return
      enabled = on
      if (on) { begin(); return }
      silence(TIMING.quickFade, false)
      paused?.voice.dispose()
      paused = null
    },
    setForeground(visible) {
      if (visible === foreground || destroyed) return
      foreground = visible
      if (visible) begin()
      else silence(TIMING.quickFade, true)
    },
    unlock() {
      unlocked = true
      if (mode === 'idle' && !pending && voices.size === 0) begin()
    },
    destroy() {
      destroyed = true
      generation += 1
      if (wake) clearTimer(wake)
      discardPending()
      for (const voice of voices) voice.dispose()
      voices.clear()
      paused?.voice.dispose()
      paused = null
    },
  }
}
```

Notes for the implementer:
- `setContext` with nothing audible and no transition (before the first piece
  starts, or after turning on) restarts the pending choice immediately rather
  than imposing a settle; transitions apply once music has played.
- `discardPending` leaves a voice whose `play()` is in flight to the
  fulfillment handler, which disposes it.
- Failure lockout survives toggle and foreground changes. Only an identity
  change releases it, including an identity change received while disabled or
  away. At the third failure, cancel pending work and fade audible music out
  over one second; progress events cannot start further preparations.
- While away, retain the current port voice even during an overlap; retire
  the older outgoing voice. On return, resume the retained playback position.
- The fake voice advances media time with the test clock while playing and
  freezes it on pause. Advancing a timer must also advance playback position.

- [ ] **Step 3: Run until green**

Run: `node --test test/desktop/music-transitions.test.mjs`. Expected: all
pass. If a timeline assertion fails, fix the director, not the test: every
timestamp in these tests comes from DESIGN.md or the spec.

- [ ] **Step 4: Break it**

- In `select()`, change `transition.outgoingEndsAt + TIMING.silence` to
  `t + TIMING.settle` → the reselection test fails; restore.
- In `start()`, move `onStart(...)` before `voice.play()` → the late-audio
  and superseded tests fail; restore.
- In the `onProgress` handler, drop `|| transition` → the
  selection-before-end test fails; restore.
- Remove `failureLocked = true` from `fail()` → the failure-lock tests fail
  after toggle or foreground changes; restore.
- Add `&& voices.size === 1` to the retained-port condition in `silence()` →
  both overlap-resume tests fail; restore.

- [ ] **Step 5: Commit**

```bash
npm run desktop:test
git add assets/js/music_transitions.js test/desktop/music-transitions.test.mjs
git commit -m "Add the background music transition director

Owns selection fades, automatic crossfades, silent waits, disabling,
hiding and resuming, with generation checks so superseded audio never
plays or earns a credit.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 12: Music hook, design documentation and inventory

**Files:**
- Create: `assets/js/music.js`
- Create: `test/desktop/music-hook.test.mjs`
- Modify: `assets/js/app.js`
- Modify: `lib/tijara_tides_web/components/game/music_panel.ex` (add `phx-hook="Music"`)
- Modify: `docs/DESIGN.md`, `scripts/gen-ux-inventory.py`, `docs/ux-inventory.md` (regenerated), `docs/IMPLEMENTATION.md`

**Interfaces:**
- Consumes: Tasks 8–11.
- Produces: hook `Music`; helpers `readSettings(storage)`, `saveSettings(storage, settings)`, `creditText(template, track)`, `DEFAULTS`.
  `#music-credit` gains `data-started` (space-separated slugs in start
  order) for the browser contract. It lives on a child of the
  `phx-update="ignore"` container because LiveView removes `data-*`
  attributes the server did not render from the ignored container itself.

- [ ] **Step 1: Failing tests**

`test/desktop/music-hook.test.mjs`:

```js
import {test, afterEach} from 'node:test'
import assert from 'node:assert/strict'
import {readFileSync} from 'node:fs'
const uri = source => `data:text/javascript;base64,${Buffer.from(source).toString('base64')}`
const read = name => readFileSync(new URL(`../../assets/js/${name}.js`, import.meta.url), 'utf8')
const hookSource = read('music')
  .replace('"./music_policy"', JSON.stringify(uri(read('music_policy'))))
  .replace('"./music_engine"', JSON.stringify(uri(read('music_engine'))))
  .replace('"./music_transitions"', JSON.stringify(uri(read('music_transitions'))))
const {Music, readSettings, saveSettings, creditText, DEFAULTS} = await import(uri(hookSource))
const flush = () => new Promise(resolve => setImmediate(resolve))

function storage(initial = {}) {
  const values = {...initial}
  return {values, getItem: key => values[key] ?? null, setItem: (key, value) => { values[key] = value }}
}

test('first launch is enabled at 30; saved settings persist; bad storage is tolerated', () => {
  assert.deepEqual(readSettings(storage()), {enabled: true, volume: 30})
  assert.deepEqual(DEFAULTS, {enabled: true, volume: 30})
  assert.deepEqual(readSettings(storage({'tijara.music.enabled': 'false', 'tijara.music.volume': '72'})),
    {enabled: false, volume: 72})
  assert.deepEqual(readSettings(storage({'tijara.music.volume': '999'})), {enabled: true, volume: 30})
  const throwing = {getItem() { throw new Error('denied') }, setItem() { throw new Error('denied') }}
  assert.deepEqual(readSettings(throwing), DEFAULTS)
  saveSettings(throwing, {enabled: false, volume: 10})
  const s = storage()
  saveSettings(s, {enabled: false, volume: 10})
  assert.deepEqual(s.values, {'tijara.music.enabled': 'false', 'tijara.music.volume': '10'})
})

test('credit text fills named placeholders literally', () => {
  assert.equal(creditText('Now playing: %{title} by %{artists}', {title: 'A $& B', artists: ['X', 'Y']}),
    'Now playing: A $& B by X, Y')
})

const restores = []
afterEach(() => { while (restores.length) restores.pop()() })

function element(id) {
  const listeners = {}
  return {id, hidden: false, textContent: '', dataset: {}, attributes: {}, value: '30', href: '',
    setAttribute(name, value) { this.attributes[name] = String(value) },
    addEventListener(type, fn) { listeners[type] = fn }, removeEventListener(type) { delete listeners[type] },
    fire(type) { listeners[type]?.({}) }}
}

function mountHook({music = 'available', fetchResult} = {}) {
  const nodes = Object.fromEntries(['music-controls', 'music-toggle', 'music-volume', 'music-credit'].map(id => [id, element(id)]))
  const el = {dataset: {music, manifest: '/audio/fixtures/music.json', context: 'port', port: 'Tangier',
    nowPlaying: 'Now playing: %{title} by %{artists}', labelOn: 'Turn music on', labelOff: 'Turn music off'},
    querySelector: selector => nodes[selector.slice(1)]}
  const local = storage()
  const timeouts = []
  const saved = {setTimeout: globalThis.setTimeout, clearTimeout: globalThis.clearTimeout}
  restores.push(() => Object.assign(globalThis, saved))
  Object.assign(globalThis, {
    localStorage: local,
    location: {href: 'https://h.test/play'},
    performance: {now: () => 0},
    setTimeout: (fn, ms) => { timeouts.push({fn, ms}); return timeouts.length },
    clearTimeout: () => {},
    document: {hidden: false, hasFocus: () => true, addEventListener() {}, removeEventListener() {}},
    window: {addEventListener() {}, removeEventListener() {}},
    Audio: class { canPlayType() { return 'probably' } },
    AudioContext: class {
      constructor() { this.currentTime = 0; this.destination = {} }
      createGain() { return {gain: {value: 0, cancelScheduledValues() {}, setValueAtTime() {}, linearRampToValueAtTime() {}, setValueCurveAtTime() {}}, connect() {}, disconnect() {}} }
      createMediaElementSource() { return {connect() {}, disconnect() {}} }
      resume() { return Promise.resolve() }
      close() { return Promise.resolve() }
    },
    fetch: async () => fetchResult ?? {ok: true, json: async () => ({palettes: [], tracks: {}})},
  })
  const hook = {...Music, el}
  return {hook, nodes, local, timeouts}
}

test('toggle and volume persist and update the control', async () => {
  const {hook, nodes, local} = mountHook()
  await Music.mounted.call(hook)
  assert.equal(nodes['music-controls'].hidden, false)
  assert.equal(nodes['music-toggle'].attributes['aria-pressed'], 'true')
  nodes['music-toggle'].fire('click')
  assert.equal(local.values['tijara.music.enabled'], 'false')
  assert.equal(nodes['music-toggle'].attributes['aria-pressed'], 'false')
  assert.equal(nodes['music-toggle'].attributes['aria-label'], 'Turn music on')
  nodes['music-volume'].value = '55'
  nodes['music-volume'].fire('input')
  assert.equal(local.values['tijara.music.volume'], '55')
  Music.destroyed.call(hook)
})

test('the credit names the piece, links its source and hides after eight seconds', async () => {
  const {hook, nodes, timeouts} = mountHook()
  await Music.mounted.call(hook)
  hook.showCredit({title: 'Shenyang', artists: ['Kevin MacLeod'], source_url: 'https://s.test'}, 'shenyang')
  const credit = nodes['music-credit']
  assert.equal(credit.textContent, 'Now playing: Shenyang by Kevin MacLeod')
  assert.equal(credit.href, 'https://s.test')
  assert.equal(credit.hidden, false)
  assert.equal(nodes['music-credit'].dataset.started, 'shenyang')
  const hide = timeouts.find(t => t.ms === 8000)
  hide.fn()
  assert.equal(credit.hidden, true)
  Music.destroyed.call(hook)
})

test('hides controls when music is unavailable or the browser cannot play Opus', async () => {
  const off = mountHook({music: 'unavailable'})
  await Music.mounted.call(off.hook)
  assert.equal(off.nodes['music-controls'].hidden, true)
  const noOpus = mountHook()
  globalThis.Audio = class { canPlayType() { return '' } }
  await Music.mounted.call(noOpus.hook)
  assert.equal(noOpus.nodes['music-controls'].hidden, true)
})

test('hides controls when the manifest cannot load', async () => {
  const broken = mountHook({fetchResult: {ok: true, json: async () => { throw new SyntaxError('bad') }}})
  await Music.mounted.call(broken.hook)
  assert.equal(broken.nodes['music-controls'].hidden, true)
  const missing = mountHook({fetchResult: {ok: false, json: async () => ({})}})
  await Music.mounted.call(missing.hook)
  assert.equal(missing.nodes['music-controls'].hidden, true)
  await flush()
})
```

Run: `node --test test/desktop/music-hook.test.mjs` → FAIL.

- [ ] **Step 2: Implement the hook**

`assets/js/music.js`:

```js
import {readContext, identity, choosePiece} from "./music_policy"
import {createEngine} from "./music_engine"
import {createDirector} from "./music_transitions"

const ENABLED_KEY = 'tijara.music.enabled'
const VOLUME_KEY = 'tijara.music.volume'
const CREDIT_MS = 8000
export const DEFAULTS = Object.freeze({enabled: true, volume: 30})

const storage = () => { try { return globalThis.localStorage } catch { return null } }

export function readSettings(store) {
  const settings = {...DEFAULTS}
  try {
    const enabled = store?.getItem(ENABLED_KEY)
    if (enabled === 'true' || enabled === 'false') settings.enabled = enabled === 'true'
    const volume = Number(store?.getItem(VOLUME_KEY) ?? NaN)
    if (Number.isInteger(volume) && volume >= 0 && volume <= 100) settings.volume = volume
  } catch { /* storage unavailable: defaults apply for this visit */ }
  return settings
}

export function saveSettings(store, {enabled, volume}) {
  try {
    store?.setItem(ENABLED_KEY, String(enabled))
    store?.setItem(VOLUME_KEY, String(volume))
  } catch { /* storage unavailable: settings last for this visit */ }
}

export const creditText = (template, track) =>
  template.replace('%{title}', () => track.title).replace('%{artists}', () => track.artists.join(', '))

const supported = () => typeof globalThis.AudioContext === 'function' && typeof globalThis.Audio === 'function' &&
  new Audio().canPlayType('audio/ogg; codecs=opus') !== ''

const isForeground = () => !document.hidden && (document.hasFocus?.() ?? true)

export const Music = {
  async mounted() {
    this.controls = this.el.querySelector('#music-controls')
    this.toggle = this.el.querySelector('#music-toggle')
    this.volume = this.el.querySelector('#music-volume')
    this.credit = this.el.querySelector('#music-credit')
    if (this.el.dataset.music !== 'available' || !supported()) { this.controls.hidden = true; return }
    this.settings = readSettings(storage())
    this.started = []
    this.render()
    let manifest
    try {
      const response = await fetch(this.el.dataset.manifest)
      if (!response.ok) throw new Error(`manifest HTTP ${response.status}`)
      manifest = await response.json()
    } catch (error) {
      console.warn('Background music manifest unavailable:', error)
      this.controls.hidden = true
      return
    }
    if (this.gone) return
    this.context = new AudioContext()
    const baseUrl = new URL('.', new URL(this.el.dataset.manifest, location.href)).href
    this.engine = createEngine({context: this.context, createAudio: () => new Audio(), baseUrl})
    this.engine.setVolume(this.settings.volume)
    this.director = createDirector({manifest, engine: this.engine, policy: {identity, choosePiece},
      now: () => performance.now() / 1000,
      setTimer: (fn, ms) => setTimeout(fn, ms), clearTimer: handle => clearTimeout(handle),
      onStart: (track, slug) => this.showCredit(track, slug)})
    this.director.setEnabled(this.settings.enabled)
    this.director.setForeground(isForeground())
    this.director.setContext(readContext(this.el.dataset))
    this.onToggle = () => {
      this.settings.enabled = !this.settings.enabled
      saveSettings(storage(), this.settings)
      this.render()
      this.director.setEnabled(this.settings.enabled)
    }
    this.onVolume = () => {
      this.settings.volume = Number(this.volume.value)
      saveSettings(storage(), this.settings)
      this.engine.setVolume(this.settings.volume)
    }
    this.onFocus = () => this.director.setForeground(isForeground())
    this.onGesture = () => {
      document.removeEventListener('pointerdown', this.onGesture, true)
      document.removeEventListener('keydown', this.onGesture, true)
      this.engine.unlock().then(() => this.director?.unlock(), error => console.warn('Audio unlock failed:', error))
    }
    this.toggle.addEventListener('click', this.onToggle)
    this.volume.addEventListener('input', this.onVolume)
    document.addEventListener('visibilitychange', this.onFocus)
    window.addEventListener('focus', this.onFocus)
    window.addEventListener('blur', this.onFocus)
    document.addEventListener('pointerdown', this.onGesture, true)
    document.addEventListener('keydown', this.onGesture, true)
  },
  updated() { this.director?.setContext(readContext(this.el.dataset)) },
  destroyed() {
    this.gone = true
    this.toggle?.removeEventListener('click', this.onToggle)
    this.volume?.removeEventListener('input', this.onVolume)
    document.removeEventListener('visibilitychange', this.onFocus)
    window.removeEventListener('focus', this.onFocus)
    window.removeEventListener('blur', this.onFocus)
    document.removeEventListener('pointerdown', this.onGesture, true)
    document.removeEventListener('keydown', this.onGesture, true)
    clearTimeout(this.creditTimer)
    this.director?.destroy()
    this.context?.close()
  },
  render() {
    const {enabled, volume} = this.settings
    this.toggle.setAttribute('aria-pressed', enabled)
    this.toggle.setAttribute('aria-label', enabled ? this.el.dataset.labelOff : this.el.dataset.labelOn)
    this.toggle.textContent = enabled ? '🔊' : '🔇'
    this.volume.value = String(volume)
  },
  showCredit(track, slug) {
    this.credit.textContent = creditText(this.el.dataset.nowPlaying, track)
    this.credit.href = track.source_url
    this.credit.hidden = false
    this.started.push(slug)
    this.credit.dataset.started = this.started.join(' ')
    clearTimeout(this.creditTimer)
    this.creditTimer = setTimeout(() => { this.credit.hidden = true }, CREDIT_MS)
  },
}
```

In `assets/js/app.js`, add `import {Music} from "./music"` after the
`ShipBerth` import and `Music` to the hooks object. In `MusicPanel.panel`,
add `phx-hook="Music"` to the `#music` div.

- [ ] **Step 3: Run, break**

`node --test test/desktop/music-hook.test.mjs` → PASS. Change `CREDIT_MS`
to `5000` → the credit test fails; restore. `npm run desktop:test`.

- [ ] **Step 4: Design documentation**

In `docs/DESIGN.md`'s Background music section, add this paragraph after the
paragraph ending "with short crossfades between tracks.":

```markdown
Each piece is a whole recording that plays to its natural ending. Two seconds
before it ends, the next piece starts with a two-second crossfade using the
same gain curves. A piece started by a selection may begin at an approved entry
point that skips a very quiet opening; later repeats start from the beginning.
Selecting another sailing ship whose origin and destination share palettes with
the current voyage continues the current piece, and a diversion that changes
the destination's palette changes the musical context.
```

After the paragraph ending "remains a tuning decision.":

```markdown
The volume slider runs from 0 to 100 and starts at 30; gain is the square of
the slider's fraction. Turning music off fades it out over one second. Music
starts only after the player's first click or key press on the page.
```

After the paragraph ending "the saved music toggle or volume setting.":

```markdown
Switching away fades music out over one second. On return, port music resumes
where it paused, while voyage music chooses a fresh piece.
```

After the sentence ending "with a link to that recording's source page.", in
a new paragraph:

```markdown
A music credits page, linked from the music controls, lists every track's
title, credited creators, source, license and edits.
```

Rewrap every touched paragraph.

- [ ] **Step 5: Inventory**

Add to `REQUIREMENTS` in `scripts/gen-ux-inventory.py`, after id 214:

```python
    (215, "Each piece is a whole recording that plays to its natural ending.", 1, "audio", "Background music"),
    (216, "Two seconds before it ends, the next piece starts with a two-second crossfade using the same gain curves.", 1, "audio", "Background music"),
    (217, "A piece started by a selection may begin at an approved entry point that skips a very quiet opening; later repeats start from the beginning.", 1, "audio", "Background music"),
    (218, "Selecting another sailing ship whose origin and destination share palettes with the current voyage continues the current piece, and a diversion that changes the destination's palette changes the musical context.", 1, "audio", "Background music"),
    (219, "The volume slider runs from 0 to 100 and starts at 30; gain is the square of the slider's fraction.", 1, "input", "Background music"),
    (220, "Turning music off fades it out over one second.", 1, "audio", "Background music"),
    (221, "Music starts only after the player's first click or key press on the page.", 1, "audio", "Background music"),
    (222, "On return, port music resumes where it paused, while voyage music chooses a fresh piece.", 1, "audio", "Background music"),
    (223, "A music credits page, linked from the music controls, lists every track's title, credited creators, source, license and edits.", 1, "display", "Background music"),
```

Run `python3 scripts/gen-ux-inventory.py` and
`mix test test/docs/ux_inventory_test.exs`. If the tripwire test reports a new
requirement-sentence count, read which added sentences it counts, set
`TRIPWIRE` to the reported number, regenerate and rerun until it passes.

- [ ] **Step 6: Implementation status**

Append to `docs/IMPLEMENTATION.md`:

```markdown
## Background music

Regional port and voyage music follows the player's latest explicit ship or
port selection. GameLive keeps that focus and renders the musical context; the
browser chooses pieces from twelve palettes, owns every fade, crossfade and
silent wait, and persists the toggle and volume on the device. Twenty-eight
gain-matched Opus recordings are stored in Git LFS and credited in game and in
`docs/music-credits.md`. Production playback is off until the release listening
gate records approvals for every recording, selection entry, repeat and
handoff; developers can audition with `TIJARA_MUSIC_AUDITION=true`.
```

- [ ] **Step 7: Gates and commit**

`mix precommit`, `python3 scripts/test-game-db.py`, `npm run desktop:test`,
`python3 scripts/check-generated.py --docs-only`; zero warnings.

```bash
git add assets/js lib test/desktop docs scripts/gen-ux-inventory.py
git commit -m "Play background music in the browser

Adds the Music hook with device settings, autoplay unlock, foreground
handling and credits, and documents the playback rules in DESIGN.md
and the UX inventory.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 13: Browser contract

**Files:**
- Create: `test/browser/music.mjs`
- Modify: `test/browser/browser_contracts_test.exs`

**Interfaces:**
- Consumes: fixture soundtrack (Task 4), `#music-credit[data-started]`,
  `#music-credit`, `#music-toggle`, `#music-volume`, `#port-selector select`.

- [ ] **Step 1: The Playwright script**

```js
import {chromium} from '@playwright/test'
import {readFile} from 'node:fs/promises'
import assert from 'node:assert/strict'
import {traceRecorder} from './support/trace.mjs'

// Background music waits for a gesture, follows explicit selections with
// DESIGN.md's timing even when audio arrives late, never lets a superseded
// piece become audible, and keeps its settings across reloads.
const config = JSON.parse(await readFile(process.argv[2], 'utf8'))
const browser = await chromium.launch({headless: true})
const timer = setTimeout(() => { process.exitCode = 1; browser.close() }, 110_000)
const trace = traceRecorder('music')
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms))
const started = page => page.locator('#music-credit').evaluate(el => (el.dataset.started ?? '').split(' ').filter(Boolean))

async function open(label) {
  const context = await browser.newContext()
  await trace.attach(context, label)
  const page = await context.newPage()
  page.setDefaultTimeout(15_000)
  await page.goto(config.url + '/play')
  await page.locator('[data-phx-main].phx-connected').waitFor()
  await page.locator('#music[data-music="available"]').waitFor({state: 'attached'})
  return {context, page}
}

async function gestureAndEast(page) {
  await page.locator('.game-tagline').click()
  await page.waitForFunction(() => document.querySelector('#music-credit').dataset.started?.includes('east-port'))
}

function delayWest(page, ms) {
  return page.route('**/audio/fixtures/west-port.ogg*', async route => { await sleep(ms); await route.continue() })
}

try {
  {
    const {context, page} = await open('music-timing')
    await sleep(1_500)
    assert.deepEqual(await started(page), [], 'nothing plays before the first gesture')
    await gestureAndEast(page)
    const credit = page.locator('#music-credit')
    await credit.waitFor({state: 'visible'})
    assert.equal(await credit.textContent(), 'Now playing: East Harbour Tone by Fixture Composer')
    assert.equal(await credit.getAttribute('href'), 'https://example.test/east-port')

    await delayWest(page, 6_000)
    const t0 = Date.now()
    await page.selectOption('#port-selector select', 'Tangier')
    await page.waitForFunction(() => document.querySelector('#music-credit').dataset.started?.includes('west-port'), null, {timeout: 20_000})
    const elapsed = (Date.now() - t0) / 1000
    assert.ok(elapsed >= 5.5, `late audio must not start before it arrives (${elapsed}s)`)
    assert.equal(await credit.textContent(), 'Now playing: West Harbour Tone by Fixture Composer')
    await trace.close(context)
  }
  {
    const {context, page} = await open('music-superseded')
    await gestureAndEast(page)
    await delayWest(page, 6_000)
    await page.selectOption('#port-selector select', 'Tangier')
    await sleep(1_000)
    await page.selectOption('#port-selector select', 'Guangzhou')
    await sleep(12_000)
    const log = await started(page)
    assert.ok(!log.includes('west-port'), `superseded piece played: ${log}`)
    assert.equal(log.at(-1), 'east-port')
    await trace.close(context)
  }
  {
    const {context, page} = await open('music-disabled')
    await gestureAndEast(page)
    await delayWest(page, 6_000)
    await page.selectOption('#port-selector select', 'Tangier')
    await sleep(1_000)
    await page.locator('#music-toggle').click()
    await sleep(9_000)
    assert.ok(!(await started(page)).includes('west-port'), 'disabled music must not start the delayed piece')
    assert.equal(await page.locator('#music-toggle').getAttribute('aria-pressed'), 'false')
    await page.locator('#music-settings summary').click()
    await page.locator('#music-volume').fill('70')
    await page.reload()
    await page.locator('[data-phx-main].phx-connected').waitFor()
    await page.waitForFunction(() => document.querySelector('#music-toggle').getAttribute('aria-pressed') === 'false')
    assert.equal(await page.locator('#music-volume').inputValue(), '70')
    await trace.close(context)
  }
  console.log('Music browser contracts passed')
} catch (error) {
  console.error(error)
  process.exitCode = 1
} finally {
  clearTimeout(timer)
  await browser.close()
}
```

- [ ] **Step 2: The ExUnit driver**

Add to `test/browser/browser_contracts_test.exs`:

```elixir
  @tag timeout: 120_000
  test "Chromium background music follows selections and tolerates late audio" do
    Sql.with_world(fn c ->
      TijaraTides.WebFormFixture.session(c)
      path = Path.join(System.tmp_dir!(), "tj-music-#{c.world}.json")

      try do
        File.write!(path, Jason.encode!(%{url: url()}))
        File.chmod!(path, 0o600)

        {output, status} =
          System.cmd("node", ["test/browser/music.mjs", path], stderr_to_stdout: true)

        assert status == 0, output
        assert output =~ "Music browser contracts passed"
      after
        File.rm(path)
      end
    end)
  end
```

- [ ] **Step 3: Run and break**

Run `python3 scripts/test-browser.py`. Expected: all browser contracts pass.
Break once: in `music_transitions.js` `start()`, skip the
`gen !== generation` check (keep only `destroyed`) → the superseded scenario
fails; restore.

- [ ] **Step 4: Gates and commit**

```bash
git add test/browser
git commit -m "Add the background music browser contract

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 14: Manual probes and full gates

**Files:**
- Modify: `docs/music-recording-audit.md` (probe results), `docs/desktop.md` if relevant

- [ ] **Step 1: Desktop webview probe (macOS)**

Run the server with audition enabled and the desktop client:

```bash
TIJARA_MUSIC_AUDITION=true TIJARA_MUSIC_ENABLED=true mix phx.server
```

and `npm run desktop:dev` pointed at `http://localhost:4000`. Click once in
the game; a credit must appear and music must be audible. In Web Inspector,
`new Audio().canPlayType('audio/ogg; codecs=opus')` must be non-empty. **If
Opus does not play, stop**: an AAC fallback changes the asset design.

- [ ] **Step 2: Rapid reselection listening check**

In Chromium against the same server, start with Chinese coast port music
playing. At zero seconds, select Valencia; select Athens at one second (same
Mediterranean palette, so the pending choice and its deadline continue). At
two seconds, select Busan. The original outgoing fade ends at five seconds;
Korean port music fades in from six to eight seconds, provided it is ready.
Record what was heard. Also select Athens while Valencia's music is fully
playing: the same piece must continue at its current position without fading.

- [ ] **Step 3: Record**

Add a section `## Client playback probes` to the end of
`docs/music-recording-audit.md` recording the date, platform and browser
versions, and the outcome of Steps 1–2. Hard-wrap at 80 columns.

- [ ] **Step 4: Full gates and commit**

```bash
scripts/check-local.sh --full
```

Expected: pass with zero warnings. Commit:

```bash
git add docs
git commit -m "Record client playback probes for background music

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 15: Release listening gate and production enablement (user-led)

This task records the player's listening decisions; an agent cannot make them.

- [ ] **Step 1: Audition**

Run with `TIJARA_MUSIC_AUDITION=true TIJARA_MUSIC_ENABLED=true` locally. For
each of the 28 tracks, the user listens to the complete source recording (no
lyrics, wordless singing, choir or chanting; suitable for background play), the
encoded selection entry, and a whole-recording repeat including its natural
decay and the two-second blend. For each palette, audition every port-to-voyage
pairing (16), and at least one cross-region automatic voyage handoff and its
reverse.

These must be two voyage recordings from different palettes. Record both
directions for each reviewed cross-region pair; a track repeating itself or
two tracks from one palette cannot stand in for these auditions.

- [ ] **Step 2: Record approvals**

For each decision the user gives, add an entry to `priv/music/approvals.json`
in the shape `scripts/make-music-fixture.py`'s `approve_all` writes (copy the
bound hashes, `entry_s` and `recipe` from `priv/audio/music.json`), with the
user's date, notes and reviewed passages. Run
`mix test test/docs/music_approvals_test.exs`: no stale entries, and the
pending list shrinks to nothing. Summarize decisions in
`docs/music-recording-audit.md`.

The server rejects cross-region records outside the voyage pools and reports
a missing reverse as pending. Require the approval report to contain only
approved entries before enabling production; deleting the reverse or replacing
the pair with a self-repeat must keep playback unavailable.

- [ ] **Step 3: Enable (ask first)**

With the user's go-ahead, add to `render.yaml`'s `envVars`:

```yaml
      - key: TIJARA_MUSIC_ENABLED
        value: "true"
```

Commit, push and confirm on the deployed game that `#music` reports
`data-music="available"` and music plays after the first click.
