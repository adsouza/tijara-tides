#!/usr/bin/env python3
"""Bounded opt-in audit. Every source mutation lives in a disposable checkout.

Curated: at most 12 exact patches per invocation. Generated: pinned Muex operators,
20 candidates/source and 60/audit. One worker, seed 12345. Each mutant compiles
under the 120-second diagnostic budget; its tests then get 30 seconds.
Baseline/restoration and survivor triage are separate checks, never counted as kills.
"""
import argparse
import difflib
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import tempfile
import time

from disposable_postgres import cluster, environment

ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / "test/fixtures/mutation_faults"
MUEX_SHA = "a0898a28179e279e603a1e1e8ab25dc9e9a40791cfd0409ea093d2d6c7800cb7"
PROPERTIES = ["test/tijara_tides/use_cases/lifecycle_fuzzer_test.exs",
              "test/tijara_tides/use_cases/command_payload_properties_test.exs",
              "test/tijara_tides/domain/codec_properties_test.exs"]
# Explicit scopes include indirect callers. Muex dependency selection is not used.
SCOPES = {
    "finance": ("domain/company_finance/loan_actions.ex", ["domain/loan_actions_test.exs", "domain/finance_test.exs", "domain/company_finance_aggregate_test.exs", "domain/guarantees_test.exs"]),
    "markets": ("domain/port_cargo_market.ex", ["domain/port_cargo_market_aggregate_test.exs", "domain/market_transitions_test.exs", "domain/market_eligibility_test.exs", "domain/game_test.exs", "domain/graded_books_test.exs", "domain/market_quote_properties_test.exs"]),
    "accounts": ("domain/account.ex", ["domain/account_aggregate_test.exs", "domain/account_root_test.exs", "domain/identity_history_test.exs", "domain/email_identity_test.exs", "domain/guarantees_test.exs", "domain/account_quota_properties_test.exs"]),
}


def save(path, value):
    path.write_text(json.dumps(value, indent=2) + "\n")


def run(work, env, out, label, args, timeout=30):
    started = time.monotonic()
    log = out / (label + ".log")
    with log.open("wb") as stream:
        proc = subprocess.Popen(args, cwd=work, env=env, stdout=stream,
                                stderr=subprocess.STDOUT, start_new_session=True)
        try:
            code = proc.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            os.killpg(proc.pid, signal.SIGKILL)
            proc.wait()
            code = "timeout"
    return {"exit": code, "seconds": round(time.monotonic() - started, 2),
            "args": args, "log": str(log)}


def classify(result, witness=None):
    text = Path(result["log"]).read_text(errors="replace")
    failures = re.findall(r"^\s*\d+\) ((?:test|property) .+)$", text, re.M)
    result["failing_tests"] = failures
    if result["exit"] == "timeout":
        return "timeout"
    if re.search(r"Compilation error|\*\* \((?:CompileError|SyntaxError|TokenMissingError)\)", text):
        return "invalid_compile"
    if re.search(r"failed to start child|could not start child|failure on setup_all callback|\.__ex_unit_setup_(?:all_)?\d+/1", text):
        return "setup_failure"
    if result["exit"] == 0:
        return "survived"
    if result["exit"] == 2 and failures and (not witness or re.search(witness, text)):
        return "detected"
    return "harness_failure"


def isolated(directory):
    work = Path(directory) / "repo"
    shutil.copytree(ROOT, work, ignore=shutil.ignore_patterns(
        ".git", "deps", "node_modules", "_build", "cover", "tmp", "target", "dist", ".env*"))
    (work / "deps").symlink_to(ROOT / "deps", target_is_directory=True)
    shutil.copytree(ROOT / "_build", work / "_build", symlinks=True)
    return work


def mutant(work, env, out, label, args, witness=None):
    # Recompiling dependents must not consume the 30-second test budget.
    build = run(work, env, out, label + "-compile", ["mix", "compile"], 120)
    if build["exit"] != 0:
        return build, classify(build, witness)
    fault = run(work, env, out, label, args)
    return fault, classify(fault, witness)


def test_args(tests):
    return ["mix", "test", *tests, "--seed", "12345"]


def touch_source(path, text, stamp):
    path.write_text(text)
    # Mix compares whole-second source mtimes. Advance the isolated source's
    # timestamp without sleeps so same-sized operator replacements recompile.
    os.utime(path, (stamp, stamp))


def curated(work, base_env, out, start, count):
    catalogue = json.loads((FIXTURES / "catalogue.json").read_text())
    selected = catalogue[start:start + count]
    if not selected:
        raise SystemExit("No curated faults in selected range")
    reports = []
    stamp = int(time.time())
    for index, item in enumerate(selected):
        name = item["name"]
        patch = FIXTURES / item["patch"]
        headers = re.findall(r"^(?:---|\+\+\+) (.+)$", patch.read_text(), re.M)
        if len(headers) != 2 or headers[0] != headers[1]:
            raise SystemExit("Curated faults must change exactly one existing source file")
        source = headers[0]
        path = work / source
        if not path.resolve().is_relative_to((work / "lib").resolve()):
            raise SystemExit("Curated source must be inside isolated lib/")
        original = path.read_text()
        tests = item["tests"]
        # A fault may opt its detecting tests in, such as the CI-only control sweep.
        env = {**base_env, **item.get("env", {})}
        baseline = run(work, env, out, name + "-baseline", test_args(tests), 120)
        if baseline["exit"] != 0:
            raise SystemExit(f"Unmutated baseline failed: {baseline['log']}")
        checked = subprocess.run(["git", "apply", "--check", "-p0", str(patch)], cwd=work,
                                 capture_output=True, text=True)
        if checked.returncode:
            raise SystemExit(f"Stale fault {name}: {checked.stderr}")
        try:
            subprocess.run(["git", "apply", "-p0", str(patch)], cwd=work, check=True)
            stamp = max(stamp + 1, int(time.time()) + 1)
            os.utime(path, (stamp, stamp))
            shutil.copy(patch, out / patch.name)
            fault, classification = mutant(work, env, out, name + "-fault", test_args(tests),
                                           item["witness"])
        finally:
            stamp += 1
            touch_source(path, original, stamp)
        restored = run(work, env, out, name + "-restored", test_args(tests), 120)
        if restored["exit"] != 0:
            raise SystemExit(f"Restored baseline failed: {restored['log']}")
        row = {**item, "source_sha256": hashlib.sha256(original.encode()).hexdigest(),
               "patch_sha256": hashlib.sha256(patch.read_bytes()).hexdigest(),
               "baseline": baseline, "fault": fault, "restored": restored,
               "classification": classification}
        reports.append(row)
        save(out / "curated.json", reports)
        print(f"{start + index}: {name}: {classification}", flush=True)
    return reports


def export_generated(directory, env, out):
    import io
    import tarfile
    tool = Path(directory) / "operator-tool"
    tool.mkdir()
    archive = tool / "muex.tar"
    subprocess.run(["curl", "--fail", "--silent", "--show-error", "--max-time", "30",
                    "https://repo.hex.pm/tarballs/muex-0.11.2.tar", "-o", str(archive)], check=True)
    if hashlib.sha256(archive.read_bytes()).hexdigest() != MUEX_SHA:
        raise SystemExit("Pinned Muex archive checksum mismatch")
    with tarfile.open(archive) as outer:
        packed = outer.extractfile("contents.tar.gz").read()
    with tarfile.open(fileobj=io.BytesIO(packed), mode="r:gz") as inner:
        inner.extractall(tool / "muex", filter="data")
    (tool / "mix.exs").write_text(f'''defmodule MutationAudit.MixProject do
  use Mix.Project
  def project, do: [app: :mutation_audit, version: "0.0.0", deps: deps()]
  defp deps, do: [{{:muex, path: {json.dumps(str(tool / 'muex'))}}}, {{:jason, path: {json.dumps(str(ROOT / 'deps/jason'))}, override: true}}]
end
''')
    exporter = ROOT / "scripts/export-mutations.exs"
    target = out / "generated-candidates.json"
    tool_env = {**env, "MIX_ENV": "prod"}
    deps = run(tool, tool_env, out, "operator-dependencies", ["mix", "deps.get"], 120)
    if deps["exit"] != 0:
        raise SystemExit(f"Operator dependency setup failed: {deps['log']}")
    result = run(tool, tool_env, out, "operator-export", ["mix", "run", str(exporter), str(target),
        *[str(ROOT / ("lib/tijara_tides/" + source)) for source, _ in SCOPES.values()]], 120)
    if result["exit"] != 0:
        raise SystemExit(f"Operator export failed: {result['log']}")
    return json.loads(target.read_text())


def provenance(source, line):
    result = subprocess.run(["git", "blame", "--porcelain", "-L", f"{line},{line}", "HEAD", "--", source],
                            cwd=ROOT, capture_output=True, text=True, check=True)
    commit = result.stdout.split()[0]
    ancestry = subprocess.run(["git", "merge-base", "--is-ancestor", commit, "5ad0399"], cwd=ROOT,
                              capture_output=True, text=True)
    if ancestry.returncode not in (0, 1):
        raise SystemExit(f"Provenance base 5ad0399 is unavailable; fetch full history: {ancestry.stderr.strip()}")
    earlier = ancestry.returncode == 0
    return {"origin_commit": commit, "predates_automation_review_base": earlier}


def generated(work, directory, env, out):
    candidates = export_generated(directory, env, out)
    assert len(candidates) <= 60
    reports = []
    stamp = int(time.time())
    for area, (relative, named) in SCOPES.items():
        source = "lib/tijara_tides/" + relative
        path = work / source
        original = path.read_text()
        selected = [m for m in candidates if m["source"] == str(ROOT / source)]
        assert len(selected) <= 20
        if not selected:
            raise SystemExit(f"Candidate shortfall: zero in {area}")
        tests = ["test/tijara_tides/" + p for p in named] + PROPERTIES
        for item in selected:
            label = f"{area}-{len(reports):02}"
            stamp = max(stamp + 1, int(time.time()) + 1)
            touch_source(path, item["canonical"], stamp)
            baseline = run(work, env, out, label + "-baseline", test_args(tests), 120)
            if baseline["exit"] != 0:
                raise SystemExit(f"Canonical baseline failed: {baseline['log']}")
            patch = ''.join(difflib.unified_diff(item["canonical"].splitlines(True),
                item["mutated"].splitlines(True), fromfile=source, tofile=source))
            (out / (label + ".patch")).write_text(patch)
            try:
                stamp += 1
                touch_source(path, item["mutated"], stamp)
                fault, classification = mutant(work, env, out, label + "-fault", test_args(tests))
                triage = None
                if classification == "survived":
                    applicable = tests + ["test/tijara_tides/infrastructure/game_persistence_test.exs",
                        "test/tijara_tides/infrastructure/sql_fuzzer_test.exs",
                        "test/tijara_tides/infrastructure/sql_transition_contracts_test.exs"]
                    triage = run(work, env, out, label + "-full-applicable", test_args(applicable), 120)
                    outcome = classify(triage)
                    classification = {"detected": "selection_miss", "survived": "survived_full_applicable"}.get(outcome, "triage_" + outcome)
            finally:
                stamp += 1
                touch_source(path, original, stamp)
            restored = run(work, env, out, label + "-restored", test_args(tests), 120)
            if restored["exit"] != 0:
                raise SystemExit(f"Restoration failed: {restored['log']}")
            row = {k: v for k, v in item.items() if k not in ("canonical", "mutated")}
            row.update(area=area, source=source, baseline=baseline, fault=fault,
                       restored=restored, classification=classification, triage=triage,
                       provenance=provenance(source, item["line"]),
                       source_sha256=hashlib.sha256(original.encode()).hexdigest(),
                       patch_sha256=hashlib.sha256(patch.encode()).hexdigest())
            reports.append(row)
            save(out / "generated.json", reports)
            print(f"{label}: {classification}", flush=True)
    return reports


def replay(work, env, out, report, index, extra_tests, named_only=False):
    rows = json.loads(report.read_text())
    candidates = json.loads(report.with_name("generated-candidates.json").read_text())
    item = candidates[index]
    row = rows[index]
    source = row["source"]
    path = work / source
    if not path.resolve().is_relative_to((work / "lib").resolve()):
        raise SystemExit("Replay source must be inside isolated lib/")
    original = path.read_text()
    if hashlib.sha256(original.encode()).hexdigest() != row["source_sha256"]:
        raise SystemExit("Replay requires the source revision recorded by the audit")
    patch = ''.join(difflib.unified_diff(item["canonical"].splitlines(True),
        item["mutated"].splitlines(True), fromfile=source, tofile=source))
    if hashlib.sha256(patch.encode()).hexdigest() != row["patch_sha256"]:
        raise SystemExit("Replay patch identity mismatch")
    (out / "exact.patch").write_text(patch)
    args = row["fault"]["args"] + extra_tests
    if named_only:
        args += ["--exclude", "property"]
    stamp = int(time.time()) + 1
    touch_source(path, item["canonical"], stamp)
    baseline = run(work, env, out, "replay-baseline", args, 120)
    if baseline["exit"] != 0:
        raise SystemExit(f"Replay baseline failed: {baseline['log']}")
    try:
        touch_source(path, item["mutated"], stamp + 1)
        fault, classification = mutant(work, env, out, "replay-fault", args)
    finally:
        touch_source(path, original, stamp + 2)
    restored = run(work, env, out, "replay-restored", args, 120)
    if restored["exit"] != 0:
        raise SystemExit(f"Replay restoration failed: {restored['log']}")
    result = {"index": index, "source": source, "classification": classification,
              "baseline": baseline, "fault": fault, "restored": restored,
              "original_classification": row["classification"], "extra_tests": extra_tests,
              "named_only": named_only}
    save(out / "replay.json", result)
    print(f"Exact replay {index}: {classification}", flush=True)
    return [result]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=["curated", "generated", "replay"])
    parser.add_argument("--start", type=int)
    parser.add_argument("--count", type=int, default=12)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--report", type=Path)
    parser.add_argument("--extra-test", action="append", default=[])
    parser.add_argument("--named-only", action="store_true", help="Replay without StreamData properties for a fixed-cohort comparison")
    args = parser.parse_args()
    if args.mode == "replay" and (not args.report or args.start is None):
        parser.error("replay requires --report and --start INDEX")
    if args.mode == "curated" and args.start is None:
        args.start = 0
    if args.start is not None and args.start < 0:
        parser.error("--start must be >= 0")
    if args.mode == "curated" and not 1 <= args.count <= 12:
        parser.error("Curated ranges require count between 1 and 12")
    out = args.out.resolve()
    out.mkdir(parents=True, exist_ok=True)
    env = environment()
    for key in ("TIJARA_TEST_DB_PORT", "MIX_BUILD_PATH", "MIX_BUILD_ROOT", "TIJARA_FUZZ_EXTENDED", "TIJARA_BROWSER_TEST_PORT", "TIJARA_CONTROL_SWEEP",
                "TIJARA_CONTROL_SWEEP_FOCUS"):
        env.pop(key, None)
    env.update(MIX_ENV="test", ERL_FLAGS="+S 4")
    sha = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    save(out / "environment.json", {"source_revision": sha, "seed": 12345, "workers": 1,
         "mutant_timeout_seconds": 30, "muex_version": "0.11.2", "archive_sha256": MUEX_SHA,
         "diagnostic_timeout_seconds": 120,
         "working_tree": subprocess.check_output(["git", "status", "--porcelain"], cwd=ROOT, text=True),
         "test_source_sha256": {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest()
             for path in sorted((ROOT / "test").rglob("*"))
             if path.is_file() and path.suffix in (".ex", ".exs", ".json", ".patch")},
         "runtime": subprocess.check_output(["elixir", "--version"], text=True)})
    with tempfile.TemporaryDirectory(prefix="tijara-mutation-") as directory:
        work = isolated(directory)
        with cluster(env) as port:
            env["TIJARA_TEST_DB_PORT"] = str(port)
            if args.mode == "curated":
                reports = curated(work, env, out, args.start, args.count)
            elif args.mode == "generated":
                reports = generated(work, directory, env, out)
            else:
                reports = replay(work, env, out, args.report.resolve(), args.start, args.extra_test, args.named_only)
    failed = any(row["classification"] not in ["detected", "selection_miss"] for row in reports)
    raise SystemExit(1 if failed else 0)


if __name__ == "__main__":
    main()
