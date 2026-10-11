#!/usr/bin/env bash
# Shared server gates: CI runs this on every runtime; pre-push uses the local one.
set -euo pipefail
cd "$(dirname "$0")/.."

# Child harnesses create their own disposable databases and listeners.
unset DATABASE_URL DATABASE_URL_POOLED TIJARA_LOCAL_DB_PORT TIJARA_TEST_DB_PORT
unset MIX_ENV PHX_SERVER TIJARA_BROWSER_TEST_PORT TIJARA_CONTROL_SWEEP
unset TIJARA_FUZZ_EXTENDED TIJARA_FUZZ_CORPUS
unset TIJARA_CONTROL_SWEEP_FOCUS TIJARA_CONTROL_SWEEP_DISCOVERY
# PostgreSQL requires C on macOS; Elixir still requires UTF-8 filename encoding.
export LC_ALL=C
export ELIXIR_ERL_OPTIONS="${ELIXIR_ERL_OPTIONS:-} +fnu"
export PATH="/opt/homebrew/opt/postgresql@18/bin:/opt/homebrew/bin:$PATH"

python3 scripts/test-validation-scope.py
python3 scripts/test-server-validation.py
python3 scripts/test-mutation-audit.py
python3 scripts/test-format-staged.py
python3 -m venv tmp/check-catalogue-venv
tmp/check-catalogue-venv/bin/python -m pip install -q -r scripts/game-data-requirements.txt
tmp/check-catalogue-venv/bin/python scripts/test-catalogue-routes.py
tmp/check-catalogue-venv/bin/python scripts/check-generated.py
mix deps.get --check-locked
mix precommit
python3 scripts/check-gettext-catalogues.py
mkdir -p cover
python3 scripts/test-game-db.py --cover | tee cover/elixir-summary.txt
python3 scripts/test-game-db.py --control-sweep
npm ci
if [[ "$(uname -s)" == Linux ]]; then
  npx playwright install --with-deps chromium
else
  npx playwright install chromium
fi
mix assets.setup
# The browser harness builds test assets before starting its disposable server.
python3 scripts/test-browser.py
MIX_ENV=prod mix release --overwrite
