#!/usr/bin/env python3
"""Check shared validation admission, failure propagation and environment isolation."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent


class ServerValidationTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="tijara-server-validation-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / "scripts").mkdir()
        shutil.copyfile(ROOT / "scripts/check-server.sh", self.root / "scripts/check-server.sh")
        python = self.root / "tmp/check-catalogue-venv/bin/python"
        python.parent.mkdir(parents=True)
        python.write_text('#!/bin/bash\nprintf "catalogue %s\\n" "$*" >> "$CHECK_LOG"\n')
        python.chmod(0o755)
        self.log = self.root / "commands.log"

    def run_checks(self, fail_db=False, platform="Darwin"):
        # Export functions so the validator's macOS PATH additions cannot select
        # real tools. The real tee must preserve an upstream nonzero exit status.
        command = r'''
python3() {
  printf 'python3 %s\n' "$*" >> "$CHECK_LOG"
  if [[ "$*" == 'scripts/test-game-db.py --cover' && "$FAIL_DB" == 1 ]]; then
    return 42
  fi
}
mix() {
  for key in DATABASE_URL DATABASE_URL_POOLED TIJARA_LOCAL_DB_PORT TIJARA_TEST_DB_PORT MIX_ENV PHX_SERVER TIJARA_BROWSER_TEST_PORT TIJARA_CONTROL_SWEEP TIJARA_FUZZ_EXTENDED TIJARA_FUZZ_CORPUS TIJARA_CONTROL_SWEEP_FOCUS TIJARA_CONTROL_SWEEP_DISCOVERY; do
    if [[ "$key" != MIX_ENV || "$*" != 'release --overwrite' ]]; then
      if printenv "$key" >/dev/null; then return 43; fi
    fi
  done
  [[ "$ELIXIR_ERL_OPTIONS" == *+fnu* ]] || return 44
  printf 'mix %s\n' "$*" >> "$CHECK_LOG"
}
npm() { printf 'npm %s\n' "$*" >> "$CHECK_LOG"; }
npx() { printf 'npx %s\n' "$*" >> "$CHECK_LOG"; }
uname() { printf '%s\n' "$TEST_PLATFORM"; }
export -f python3 mix npm npx uname
exec bash scripts/check-server.sh
'''
        env = {**os.environ, "CHECK_LOG": str(self.log), "FAIL_DB": str(int(fail_db)),
               "TEST_PLATFORM": platform}
        for key in ("DATABASE_URL", "DATABASE_URL_POOLED", "TIJARA_LOCAL_DB_PORT",
                    "TIJARA_TEST_DB_PORT", "MIX_ENV", "PHX_SERVER",
                    "TIJARA_BROWSER_TEST_PORT", "TIJARA_CONTROL_SWEEP",
                    "TIJARA_FUZZ_EXTENDED", "TIJARA_FUZZ_CORPUS",
                    "TIJARA_CONTROL_SWEEP_FOCUS", "TIJARA_CONTROL_SWEEP_DISCOVERY"):
            env[key] = "must-not-reach-validation"
        return subprocess.run(["bash", "-c", command], cwd=self.root, env=env,
                              capture_output=True, text=True)

    def test_both_entrypoints_use_the_shared_server_gates(self):
        local = (ROOT / "scripts/check-local.sh").read_text().splitlines()
        workflow = (ROOT / ".github/workflows/ci.yml").read_text().splitlines()
        self.assertEqual(local.count("scripts/check-server.sh"), 1)
        self.assertEqual(sum(line.strip() == "run: scripts/check-server.sh" for line in workflow), 1)
        for lines in (local, workflow):
            for gate in ("mix precommit", "scripts/test-game-db.py", "scripts/test-browser.py"):
                self.assertFalse(any(gate in line for line in lines), gate)

    def test_full_server_admission_and_clean_environment(self):
        result = self.run_checks()
        self.assertEqual(result.returncode, 0, result.stderr)
        commands = self.log.read_text().splitlines()
        for gate in ("catalogue scripts/test-catalogue-routes.py",
                     "catalogue scripts/check-generated.py", "mix precommit",
                     "python3 scripts/check-gettext-catalogues.py",
                     "python3 scripts/test-game-db.py --cover",
                     "python3 scripts/test-game-db.py --control-sweep",
                     "python3 scripts/test-browser.py", "mix release --overwrite"):
            self.assertIn(gate, commands)
        self.assertIn("npx playwright install chromium", commands)

    def test_linux_installs_browser_system_dependencies(self):
        result = self.run_checks(platform="Linux")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("npx playwright install --with-deps chromium", self.log.read_text())

    def test_database_failure_survives_tee_and_stops_later_gates(self):
        result = self.run_checks(fail_db=True)
        self.assertEqual(result.returncode, 42, result.stderr)
        commands = self.log.read_text()
        self.assertNotIn("--control-sweep", commands)
        self.assertNotIn("npm ci", commands)
        self.assertNotIn("release --overwrite", commands)


if __name__ == "__main__":
    unittest.main()
