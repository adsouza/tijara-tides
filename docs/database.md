# PostgreSQL storage and operations

The server persists gameplay through Ecto/Postgrex. The guest connection roster
remains in memory; accounts, companies, ships, markets, and the simulation clock
are durable. Use `python3 scripts/dev-game.py` for isolated local playtests.

## Local use

The project-local `.env.local` holds the direct and pooled connection URLs. It is
ignored by Git and has owner-only permissions. It is not automatically loaded;
export it when you deliberately want a server process to use that database.
Apply the game migrations below before the first server start:

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
when connections are closed. Further lifecycle work may decide when
to stop/start database connections if that is needed to preserve the compute
budget. Reads/writes must also tolerate a dropped connection or database wake-up;
game commands use durable idempotency IDs. Active five-second simulation commits
keep the database busy while the host is awake.

## Game storage operations

With the intended database environment configured, apply migrations explicitly
before starting the game:

```sh
mix run --no-start scripts/migrate_game.exs
mix run scripts/seed_game.exs
```

The seed command starts an application owner and prints a single-use launch
invitation. Run it while the normal server is stopped; it claims ownership just
like any other application startup. It never sends email. Normal startup neither
migrates nor creates launch invitations. Back up PostgreSQL before schema changes.

## Relational game schema

Game state uses typed columns and foreign keys, rather than JSONB entity
payloads. The domain still works with pure maps in memory; `GameRows` translates
between those maps and SQL rows.

| Table | Contents and relationships |
|---|---|
| `game_worlds` | World clock, revision, and owner fencing epoch. |
| `game_accounts` | Invitation quota, bankruptcy count, inviter, active company. |
| `game_companies` | Owner account, home port, cash, reserved funds, profit, unpaid costs. |
| `game_ships` | Company, class, port, status, destination, voyage timestamps, fuel accounting. |
| `game_cargo_lots` | Permanent lot ID, parent lot, cargo type, original quantity, expiry, creation time. |
| `game_cargo_holdings` | Current ship or market location, lot ID, FIFO position, quantity, acquisition cost. |
| `game_markets` | Port and cargo type, supply, demand, budget, production time. |
| `game_ship_cargo_batches`, `game_market_stock_batches` | Read-only compatibility views over lots and holdings. |
| `game_sessions` | Hashed device credential ID, account, wall-clock expiry. |
| `game_invitations` | Hashed code ID, inviter, invitee, seed flag, status, world-clock expiry. |
| `game_notices` | Recipient account, message, world-clock creation time. |
| `game_ports`, `game_cargo_types`, `game_ship_classes` | Stable reference IDs and display names for foreign keys. |
| `game_receipts` | Account/request key, fingerprint, and variable JSONB command result for retry replay. |
| `game_journal_transactions`, `game_journal_entries` | Append-only financial events and balanced debit/credit lines. |
| `game_ledger_accounts`, `game_ledger_balances` | Chart of accounts and totals maintained by posted journal entries. |

Dynamic primary keys are scoped by `world_id`. Ownership foreign keys include
that world, so records cannot reference another world's account or company.
Account/company references are deferred until transaction commit because a single
command establishes both sides. A company's active-account link must match its
owner. Checks reject negative quantities and invalid balances, statuses, and
voyage timing. Game rules still validate capacities, prices, and other gameplay
conditions; the schema is not a replacement for domain validation.

Money columns use integer cents, quantities use integer lots, and operational
clock columns use integer milliseconds. `expires_at_ms` on sessions is Unix
wall-clock time; voyage and cargo expiry columns use the paused world clock.
Each batch has a permanent, world-scoped lot ID, allocated from the world's
transactional counter. FIFO `position` is independent of that identity. Moving
an entire lot changes its holding without changing its ID. A split retires the
parent holding and creates two child IDs that reference the parent; database
checks conserve quantity and preserve cargo type and expiry. Consumed and expired
lots retain their immutable identity records without active holdings. A lot has
at most one current location. No cargo arrays are stored as JSON.

Static tuning and map geometry remain versioned source assets. The reference
rows give those stable identifiers relational integrity; changing the catalogue's
set of IDs requires a corresponding database migration. The stored legacy ID
`Scrap aluminium` has the display name `Aluminium scrap`.

Commits update only scalar columns that changed and insert, update, or remove
changed batch rows. They retain the world-row lock, ownership check, atomic
receipt write, and publish-after-commit behavior. Command receipts intentionally
remain JSONB because different commands return different result shapes; they
are not mutable gameplay records. Bootstrap redemption receipts can precede an
account, so their account key has no account foreign key.

### Migrating an existing playtest

Stop every game owner before migration and take a PostgreSQL backup. Migration
`20260907010000_normalize_game_storage` creates the relational tables, copies all
legacy fields and batch order, validates references, and removes `game_entities`
in one transaction. Unknown legacy kinds or fields abort the migration instead
of being silently discarded. World clock, epoch, revision, and receipts are
preserved. A failed migration rolls back; returning to the legacy application
after a successful migration requires restoring the pre-migration backup.

Run the migration command above, then restart the game owner. The local launcher
runs migrations before starting its server; production startup does not.
Migration tests cover legacy round trips, rollback, references, invalid values,
and isolated batch writes. Full tests use a disposable local PostgreSQL cluster,
never the shared Neon database.

### Small maintenance updates

Stop the game owner before direct SQL edits and restart it afterward. The running
simulation caches world state; a direct edit behind it is not a live admin API
and could otherwise be overwritten. With the owner stopped, a ship rename is an
ordinary targeted update, for example:

```sql
UPDATE game_ships
SET name = 'New ship name'
WHERE world_id = 'ocean' AND id = '<ship-id>';
```

Apply coordinated edits in a transaction and preserve accounting invariants.
Money, inventory value, and ship book value must reconcile with the journal;
editing those summaries alone makes startup reconciliation fail. Financial
adjustments require new balanced journal entries together with their game-state
changes, never rewriting history. Do not edit receipt fingerprints/results or
session hashes as a shortcut to changing gameplay state.

## Permanent lots and accounting migration

Migration `20260907020000_add_lots_and_ledger` upgrades the relational schema.
It assigns IDs to existing batches without changing quantities, FIFO order,
costs, or expiry; their lineage starts at migration because earlier splits
cannot be reconstructed. Each company receives an explicit `opening_balance`
transaction covering its existing available and reserved cash, cargo cost,
ship book value, unpaid costs, and historical profit. The balancing equity
entry is an opening figure, not invented transaction history. Ship opening book
values use the current class prices because depreciation is not implemented.

Stop the owner and back up the database before applying this migration, then
restart. The migration is atomic; restoring the backup is the rollback path.
See [financial ledger](ledger.md) for posting and reconciliation rules.

## Startup connectivity status

When `DATABASE_URL` is configured, a supervised startup check runs `SELECT 1`
once and caches the result. `/statusz` returns 200 after success, or 503 while
checking, after failure, or without database configuration. Status requests never
query Neon. A configured deployment must also have a ready game owner; missing
migrations or failed gameplay persistence return 503. The cached connectivity
check alone does not continuously monitor the database. See [deployment setup](deploying.md)
for health check configuration and restart behavior.
