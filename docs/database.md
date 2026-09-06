# Neon connection

The server can now connect to Neon through Ecto/Postgrex. This is connection
infrastructure only: there are no gameplay schemas, migrations, startup hydration,
or turn writes yet. The lobby's world and roster remain in memory.

## Local use

The project-local `.env.local` holds the direct and pooled connection URLs. It is
ignored by Git and has owner-only permissions. It is not automatically loaded;
export it when you want a server process to connect:

```sh
set -a
source .env.local
set +a
mix phx.server
```

For a fresh clone, copy `.env.example` to `.env.local`, fill in the connection
strings from Neon, and run `chmod 600 .env.local`. Do not put these values in
frontend code or Tauri configuration. Desktop clients only connect to the game
server, never directly to PostgreSQL.

Verify connectivity without starting the world or changing the database:

```sh
set -a
source .env.local
set +a
mix run --no-start scripts/check_database.exs
```

This starts one temporary repository connection, runs `SELECT 1`, and closes it.
The application uses `DATABASE_URL` (direct connection); `DATABASE_URL_POOLED` is
retained for future use but is not selected automatically.

On Render, set `DATABASE_URL` in the service's secret environment settings. The
local environment file does not get deployed. Normal tests ignore the variable
and do not connect to Neon, even when it is inherited from the shell. Without
`DATABASE_URL`, the server currently continues in the original in-memory mode.

## TLS and idle traffic

DatabaseConfig enables certificate and hostname verification using the operating
system trust store and supplies SNI. It removes the Neon URL's libpq-only query
parameters so they cannot override Postgrex's explicit TLS settings.

**Driver distinction:** Postgrex 0.22.4 uses SCRAM-SHA-256 but does not implement
libpq's `channel_binding=require` option / SCRAM-SHA-256-PLUS. Keeping that text in
a URL would not enforce channel binding. This integration provides verified TLS;
it does not claim to enforce channel binding. If channel binding becomes a hard
requirement, the driver choice needs to change.

The running repository has two connections, with `idle_limit: 0` disabling
DBConnection's periodic idle pings. This avoids the default once-per-second
ping traffic. It does not guarantee Neon will stay asleep: the pool reconnects
when connections are closed. The future active-client lifecycle must decide when
to stop/start database connections if that is needed to preserve the compute
budget. Reads/writes must also tolerate a dropped connection or database wake-up;
turn retries will need durable idempotency IDs before gameplay writes are added.

## Next persistence work

After game state and action boundaries are designed:

- Add migrations for the minimum durable world/player state.
- Load the world at startup and pause its simulation when there are no clients.
- Commit only each completed action's changed records, atomically with its unique
  action ID; acknowledge and broadcast only after commit succeeds.
- Keep static definitions and derived presentation data out of repeated writes.
- Add recovery and retry integration tests against a separate disposable test
  database, never the shared Neon database used for playtesting.

## Startup connectivity status

When `DATABASE_URL` is configured, a supervised startup check runs `SELECT 1`
once and caches the result. `/statusz` returns 200 after success, or 503 while
checking, after failure, or without database configuration. Status requests never
query Neon. This proves startup connectivity only; it does not continuously
monitor the connection or load game state. See [deployment setup](deploying.md)
for health check configuration and restart behavior.
