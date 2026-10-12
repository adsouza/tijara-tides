#!/usr/bin/env python3
"""Unit tests for scripts/prepare-music.py with ffmpeg replaced by fakes."""
import hashlib
import importlib.util
import json
import math
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


class Argv(prepare_music.Tools):
    """Real Tools whose ffmpeg runs are recorded instead of executed."""

    def __init__(self):
        self.calls = []

    def run(self, *args):
        self.calls.append([str(arg) for arg in args])

        class Result:
            stdout = stderr = ""

        return Result()

    def filter(self):
        argv = self.calls[-1]
        return argv[argv.index("-af") + 1]


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
            # -6.0 measures -0.6; aim at -1.1, then one more tenth: -6.6, which measures -1.2.
            self.assertEqual(track["gain_db"], -6.6)
            self.assertLessEqual(track["true_peak_dbtp"], -1.1)
            self.assertIn("gain -6.60 dB", track["edits"])
            self.assertEqual(track["output_sha256"], digest((self.out / track["file"]).read_bytes()))
        self.assertEqual(len(tools.encoded), 4)
        self.assertEqual([row[0] for row in tools.encoded], ["a.mp3", "a.mp3", "b.mp3", "b.mp3"])

    def test_a_printed_minus_one_is_not_within_the_ceiling(self):
        # ebur128 prints tenths: -1.0 may be an actual -0.96, which is over -1.
        class RoundingTools(FakeTools):
            def loudness_log(self, path, lead, tail):
                if path.suffix == ".ogg":
                    gain = float(path.read_text().rsplit(" ", 1)[1])
                    return f"I: {-14 + gain} LUFS\nPeak: {-1.0 + gain + 6} dBFS\n"
                return super().loudness_log(path, lead, tail)

        tools = RoundingTools()
        manifest, _ = self.run_prepare(tools)
        self.assertEqual(len(tools.encoded), 4)
        for track in manifest["tracks"].values():
            # -6.0 measures -1.0, which is refused; aim at -1.1 plus a tenth: -6.2.
            self.assertEqual(track["gain_db"], -6.2)
            self.assertAlmostEqual(track["true_peak_dbtp"], -1.2)

    def test_accepts_a_printed_margin_of_a_tenth(self):
        class MarginTools(FakeTools):
            def loudness_log(self, path, lead, tail):
                if path.suffix == ".ogg":
                    return "I: -20 LUFS\nPeak: -1.1 dBFS\n"
                return super().loudness_log(path, lead, tail)

        tools = MarginTools()
        manifest, _ = self.run_prepare(tools)
        self.assertEqual(len(tools.encoded), 2)
        self.assertEqual(manifest["tracks"]["a"]["true_peak_dbtp"], -1.1)

    def test_rejects_an_encode_that_cannot_meet_the_peak_ceiling(self):
        for printed in ("-0.6", "-1.0"):
            class UnboundedTools(FakeTools):
                def loudness_log(self, path, lead, tail, printed=printed):
                    if path.suffix == ".ogg":
                        return f"I: -20 LUFS\nPeak: {printed} dBFS\n"
                    return super().loudness_log(path, lead, tail)

            tools = UnboundedTools()
            with self.subTest(printed=printed):
                with self.assertRaisesRegex(ValueError, "encoded true peak"):
                    self.run_prepare(tools)
                self.assertEqual(len(tools.encoded), 5)
                self.assertFalse((self.out / "music.json").exists())

    def assertPositiveZero(self, value):
        self.assertEqual(value, 0.0)
        self.assertEqual(math.copysign(1.0, value), 1.0, f"{value!r} is a negative zero")

    def test_rounded_values_never_print_a_negative_zero(self):
        self.assertEqual(str(prepare_music.rounded(-0.0004, 3)), "0.0")
        self.assertPositiveZero(prepare_music.rounded(-0.0004, 3))
        lead, tail = prepare_music.silence_bounds("silence_start: -0.0009\nsilence_end: -0.0004 | x\n", 60.0)
        self.assertPositiveZero(lead)
        self.assertIsNone(tail)
        self.assertPositiveZero(prepare_music.gain_db(-20.0004, -9.0, -20.0, -1.0))
        self.assertPositiveZero(prepare_music.encoded_entry(0, 0, 5.0))

    def test_a_recording_without_boundary_silence_keeps_every_sample(self):
        # A decoded length finer than the manifest's milliseconds, with no
        # silence at either end: neither side may be cut or reported.
        class Untrimmed(FakeTools):
            def duration(self, path):
                return 10.000286 if path.suffix != ".ogg" else 9.0

            def silence_log(self, path, noise_db):
                return "[silencedetect] silence_start: 4.0\n[silencedetect] silence_end: 4.5 | x\n"

        tools = Untrimmed()
        manifest, _ = self.run_prepare(tools)
        for track in manifest["tracks"].values():
            self.assertPositiveZero(track["trim_start_s"])
            self.assertPositiveZero(track["trim_end_s"])
            self.assertNotIn("silence", track["edits"])
            self.assertNotIn("0.00 s", track["edits"])
        self.assertEqual(tools.encoded[0], ("a.mp3", 0.0, None, -6.0, 64))
        argv = Argv()
        argv.encode(Path("a.mp3"), 0.0, None, -6.0, 64, Path("a.ogg"))
        self.assertEqual(argv.filter(), "asetpts=PTS-STARTPTS,volume=-6.0dB")
        argv.loudness_log(Path("a.mp3"), 0.0, None)
        self.assertEqual(argv.filter(), "ebur128=peak=true")

    def test_edits_report_only_the_trims_the_manifest_records(self):
        class TrailingOnly(FakeTools):
            def duration(self, path):
                return 10.000286 if path.suffix != ".ogg" else 9.0

            def silence_log(self, path, noise_db):
                return "[silencedetect] silence_start: 9.5\n"

        tools = TrailingOnly()
        manifest, _ = self.run_prepare(tools)
        a = manifest["tracks"]["a"]
        self.assertPositiveZero(a["trim_start_s"])
        self.assertEqual(a["trim_end_s"], 0.5)
        self.assertEqual(a["edits"], "Trimmed 0.50 s of trailing silence; gain -6.00 dB; encoded as Opus 64 kbps.")
        self.assertEqual(tools.encoded[0], ("a.mp3", 0.0, 9.5, -6.0, 64))
        argv = Argv()
        argv.encode(Path("a.mp3"), 0.0, 9.5, -6.0, 64, Path("a.ogg"))
        self.assertEqual(argv.filter(), "atrim=end=9.5,asetpts=PTS-STARTPTS,volume=-6.0dB")
        argv.encode(Path("a.mp3"), 0.5, None, -6.0, 64, Path("a.ogg"))
        self.assertEqual(argv.filter(), "atrim=start=0.5,asetpts=PTS-STARTPTS,volume=-6.0dB")
        argv.loudness_log(Path("a.mp3"), 0.5, 9.5)
        self.assertEqual(argv.filter(), "atrim=start=0.5:end=9.5,ebur128=peak=true")

    def test_encodes_constrained_vbr_opus_at_the_recipe_bitrate(self):
        argv = Argv()
        argv.encode(Path("a.mp3"), 0.5, 9.5, -6.0, 64, Path("a.ogg"))
        call = argv.calls[0]
        pairs = list(zip(call, call[1:]))
        self.assertIn(("-c:a", "libopus"), pairs)
        self.assertIn(("-b:a", "64k"), pairs)
        self.assertIn(("-vbr", "constrained"), pairs)
        self.assertIn(("-ar", "48000"), pairs)
        self.assertEqual(call[-1], "a.ogg")

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

    def test_trims_trailing_silence_ending_exactly_at_the_decoded_length(self):
        class ExplicitEndTools(FakeTools):
            def silence_log(self, path, noise_db):
                return ("[silencedetect] silence_start: 9.5\n"
                        "[silencedetect] silence_end: 10.0 | silence_duration: 0.5\n")

        manifest, _ = self.run_prepare(ExplicitEndTools())
        self.assertEqual(manifest["tracks"]["a"]["trim_end_s"], 0.5)

    def test_duration_is_the_decoded_length_not_the_container_estimate(self):
        progress = "out_time_us=100\nprogress=continue\nout_time_us=5407347\nprogress=end\n"
        self.assertEqual(prepare_music.decoded_seconds(progress), 5.407347)
        with self.assertRaisesRegex(ValueError, "decoded length missing"):
            prepare_music.decoded_seconds("progress=end\n")
        calls = []

        class Result:
            stdout = progress

        class Recorded(prepare_music.Tools):
            def run(self, *args):
                calls.append([str(arg) for arg in args])
                return Result()

        self.assertEqual(Recorded().duration(Path("x.mp3")), 5.407347)
        self.assertEqual(calls[0][0], "ffmpeg")
        self.assertIn("-progress", calls[0])
        self.assertNotIn("ffprobe", calls[0])
        lead, tail = prepare_music.silence_bounds("silence_start: 4.0\nsilence_end: 5.407347 | x\n", 5.407347)
        self.assertEqual((lead, tail), (0.0, 4.0))

    def test_silence_bounds_and_loudness_parsing(self):
        lead, tail = prepare_music.silence_bounds("silence_start: 0\nsilence_end: 1.25 | x\n", 60.0)
        self.assertEqual((lead, tail), (1.25, None))
        lead, tail = prepare_music.silence_bounds("silence_start: 58\nsilence_end: 60 | x\n", 60.0)
        self.assertEqual((lead, tail), (0.0, 58.0))
        with self.assertRaisesRegex(ValueError, "silent throughout"):
            prepare_music.silence_bounds("silence_start: 0\n", 60.0)
        self.assertEqual(prepare_music.loudness("I: -9.5 LUFS\nPeak: 0.4 dBFS\nI: -10.0 LUFS\nPeak: 0.2 dBFS\n"), (-10.0, 0.2))


if __name__ == "__main__":
    unittest.main()
