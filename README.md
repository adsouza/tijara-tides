# Tijara Tides

A multiplayer marine cargo trading game built with Elixir, OTP, Phoenix LiveView,
and Tailwind CSS. This repository currently contains the multiplayer foundation
only: a shared world and a live guest lobby. No trading, ships, cities, resources,
mines, factories, economy, or simulation clock has been implemented.

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

Run **one server instance**. Ownership is local to one BEAM node; starting multiple
replicas would create separate worlds. State is in memory and resets on restart.
Guest sessions are a development foundation, not authenticated player accounts.
There are no valuable game assets to preserve yet. Durable storage, account
security, command deduplication, and distributed ownership must be designed before
introducing a persistent multiplayer economy.

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
