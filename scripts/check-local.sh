#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Never let local validation connect to production storage.
unset DATABASE_URL DATABASE_URL_POOLED TIJARA_LOCAL_DB_PORT TIJARA_TEST_DB_PORT
unset MIX_ENV PHX_SERVER
export LC_ALL=C
export PATH="/opt/homebrew/opt/postgresql@18/bin:/opt/homebrew/bin:$PATH"

python3 -m venv tmp/check-catalogue-venv
tmp/check-catalogue-venv/bin/python -m pip install -q -r scripts/game-data-requirements.txt
tmp/check-catalogue-venv/bin/python scripts/check-generated.py
mix deps.get --check-locked
mix precommit
python3 scripts/test-game-db.py
npm ci
npm run desktop:test
python3 scripts/check-desktop-versions.py
cargo fmt --manifest-path src-tauri/Cargo.toml --check
cargo clippy --manifest-path src-tauri/Cargo.toml --locked --all-targets -- -D warnings
cargo test --manifest-path src-tauri/Cargo.toml --locked
mix assets.setup
MIX_ENV=prod mix release --overwrite
echo "Local pre-push checks passed. Docker, platform packaging, and the runtime matrix remain in CI."
