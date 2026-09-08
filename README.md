# Tijara Tides

A multiplayer marine cargo trading game built with Elixir, OTP, Phoenix LiveView,
and Tailwind CSS. The first playable milestone includes invitation-based accounts,
persistent companies, four starter fleets, manual trading, timed voyages, and a
non-Mercator world map. See [implementation scope](docs/IMPLEMENTATION.md) for
playtest limitations and the remaining milestones.

See [the game design](docs/DESIGN.md) for agreed gameplay decisions, provisional
balancing choices, and open questions for the persistent trading economy, and
[the launch port roster](docs/ports.md) for the 25 ports' economic identities
and trade roles.

## Run locally

Install Elixir and Erlang (the local versions are recorded in `.tool-versions`).
The declared minimum Elixir version is 1.19.3; CI also checks that version.
The lobby runs locally without a database or Node.js installation. Neon
connectivity is optional for local development; see [database setup](docs/database.md).
The supplied Render deployment requires `DATABASE_URL` and a successful startup
database check: its `/statusz` health check returns 503 without either. See
[deployment setup](docs/deploying.md) for configuration.

```sh
mix setup
mix phx.server
```

Visit <http://localhost:4000>. Open a different browser or a private window to join
as another guest. Tabs sharing a browser session count as one guest with multiple
connections. Counts update live when clients connect and disconnect; a dropped
network connection is removed once its server LiveView process terminates.
Use `PORT=4001 mix phx.server` if port 4000 is already occupied.

```sh
mix precommit       # formatting, forced boundary checks, and tests
```

Enable the tracked pre-push hook once per clone:

```sh
git config core.hooksPath .githooks
```

The hook runs `scripts/check-local.sh`: generated docs and catalogue checks,
Elixir validation and disposable PostgreSQL tests, desktop JavaScript tests,
version checks, Rust formatting/Clippy/tests, and a production server release
build. It requires Python with venv support, PostgreSQL, Node.js, Rust, and the
desktop build prerequisites. First runs download dependencies. Run the script
directly to check work before committing.

Pushes require a clean checkout of the commit being pushed, so uncommitted fixes
cannot hide failures in that commit. Generated artifacts are checked in a
temporary directory without rewriting working files. Database tests use only a
disposable local cluster. Docker smoke tests, native package verification, and
the alternate Elixir/OTP versions still run in CI.

## Play locally

Install PostgreSQL in addition to the tools above, then run:

```sh
python3 scripts/dev-game.py
```

The launcher creates a persistent local database under `tmp/local-game`, applies
migrations, prints a launch invitation on first use, and opens the server at
<http://localhost:4000/play>. Paste the invitation into the game, name your company,
and choose a home port and starter fleet. It ignores inherited Neon credentials.
Ctrl-C stops both services while retaining your game. Use `--seed` to issue
another launch invitation or `--web-port 4001` for another web port.

Accounts currently use a durable, revocable device credential. Email magic links,
Google linking, and cross-device recovery are a following milestone. Losing the
browser's cookie loses access to an unlinked account; use this build for playtests.

```sh
python3 scripts/test-game-db.py  # full suite against disposable local PostgreSQL
```

## Server release

For Render Free with Neon, follow [deployment setup](docs/deploying.md). The
repository includes a Dockerfile, Render Blueprint, and container CI smoke check.

```sh
mix assets.setup
MIX_ENV=prod mix release
SECRET_KEY_BASE="$(mix phx.gen.secret)" PHX_HOST=your-host.example PHX_SERVER=true \
  _build/prod/rel/tijara_tides/bin/tijara_tides start
```

A release builds and digests its own assets. Preserve a stable `SECRET_KEY_BASE`
across real deployments. Production expects HTTPS at a reverse proxy and uses
secure session cookies. Configure the proxy and `PHX_HOST` for your deployment.

Run **one server instance**. Gameplay is stored in PostgreSQL; transactional
ownership fencing rejects writes from a superseded server. The simulation resumes
from its last committed clock when a player connects, without offline catch-up.
The guest lobby remains separate and resets on restart.

See [ARCHITECTURE.md](ARCHITECTURE.md) for what was carried forward from Armchair
Metropolist, lifecycle behavior, and the boundaries for future gameplay work.

## Native desktop clients

macOS `.app` / `.dmg` and Linux `.deb` / `.flatpak` packaging are included.
The Tauri client opens a local connection screen and connects to your chosen
server; it does not run a local game engine.

```sh
npm ci
npm run desktop:dev
```

Desktop development requires Rust, Node.js, and the platform's Tauri build
prerequisites. See [desktop setup and packaging](docs/desktop.md) for build,
installation, CI, and signing details.
