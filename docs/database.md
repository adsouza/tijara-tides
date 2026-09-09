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
retained for future use but is not selected automatically. Verification and
migration use the same runtime repository configuration and print only the
target host, port, and database. All three operator commands, including seeding,
reject an environment containing both `DATABASE_URL` and `TIJARA_LOCAL_DB_PORT`; unset the unintended target first.

On Render, set `DATABASE_URL` in the service's secret environment settings. The
local environment file does not get deployed. Normal tests ignore the variable
and do not connect to Neon, even when it is inherited from the shell. Without
`DATABASE_URL` or an explicit local database, only the guest lobby is available;
durable gameplay is not configured.

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
env -u TIJARA_LOCAL_DB_PORT mix run --no-start scripts/check_database.exs
env -u TIJARA_LOCAL_DB_PORT mix run --no-start scripts/migrate_game.exs
env -u TIJARA_LOCAL_DB_PORT mix run --no-start scripts/seed_game.exs
```

The seed command validates and announces its target before starting an application
owner and printing a single-use launch invitation. The `--no-start` flag is
required: without it, Mix would boot and claim the world before the script can
validate the environment. Run it while the normal server is stopped; it claims
ownership just like any other application startup. It never sends email. Normal startup neither
migrates nor creates launch invitations. Back up PostgreSQL before schema changes.

## Release operations

The release includes `TijaraTides.Release` and the migration files; Mix and a
source checkout are unnecessary. With the intended `DATABASE_URL` and
`SECRET_KEY_BASE` supplied to the release:

```sh
bin/tijara_tides eval 'TijaraTides.Release.check_database()'
bin/tijara_tides eval 'TijaraTides.Release.migrate()'
```

These commands start only the repository and its dependencies. They neither
start the endpoint nor claim world ownership. The migrator runs pending
migrations only. For incompatible schema changes, stop gameplay before migrating.

A one-off container can run the same command from the built production image.
The private environment file below supplies the database URL and signing secret:

```sh
docker run --rm --env-file /private/path/neon.env tijara-tides:production \
  /app/bin/tijara_tides eval 'TijaraTides.Release.migrate()'
```

To seed through an existing owner, use RPC on that owner's running container:

```sh
bin/tijara_tides rpc 'IO.inspect(TijaraTides.Infrastructure.GameServer.seed())'
```

The returned single-use code is a credential; keep it private. This calls the
existing GenServer and does not increment its ownership epoch. The image
defaults to `RELEASE_DISTRIBUTION=none`, so RPC requires explicitly setting
`RELEASE_DISTRIBUTION=sname` before starting the node and using its release
cookie. An `eval` process is a different node and cannot substitute for RPC.

For the initial seed with no running server, the checkout seed script remains
available. A release-only equivalent is:

```sh
bin/tijara_tides eval 'TijaraTides.Release.seed()'
```

This last command starts a temporary world owner: keep the deployed server
stopped, unset `PHX_SERVER` in that process, and deploy or restart only after it
exits. Normal startup never seeds or migrates automatically.

## Relational game schema

Game state uses typed columns and foreign keys, rather than JSONB entity
payloads. The domain still works with pure maps in memory; `GameRows` translates
between those maps and SQL rows.

| Table | Contents and relationships |
|---|---|
| `game_worlds` | World clock, revision, and owner fencing epoch. |
| `game_accounts` | Invitation quota, bankruptcy count, inviter, active company. |
| `game_companies` | Owner account, cash, reserved funds, profit, unpaid costs. |
| `game_ships` | Company, class, port, status, destination, voyage timestamps, fuel accounting. |
| `game_cargo_lots` | Permanent lot ID, parent lot, cargo type, original quantity, expiry, creation time. |
| `game_cargo_holdings` | Current ship or market location, lot ID, FIFO position, quantity, acquisition cost. |
| `game_markets` | Port and cargo type, supply, demand, budget, production time. |
| `game_ship_cargo_batches`, `game_market_stock_batches` | Read-only compatibility views over lots and holdings. |
| `game_sessions` | Hashed device credential ID, account, wall-clock expiry. |
| `game_invitations` | Hashed code ID, inviter, invitee, seed flag, status, world-clock expiry. |
| `game_notices` | Recipient account, message, world-clock creation time; newest 100 per account. |
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
set of IDs requires a corresponding database migration. Cargo types use explicit machine IDs such as
`aluminium_scrap`, with `Aluminium scrap` as the display name.

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

## Gameplay runtime safeguards

Initial world creation has a 120-second transaction timeout to accommodate
creating the port markets over a remote database connection. Ordinary gameplay
retains the normal repository transaction timeout.

Gameplay calls share a 30-second timeout so reads can queue behind database
writes. Persistence and domain exceptions pause the world; operator logs include
the exception type and stack frames, with argument values omitted. Database
exceptions report storage unavailability, while other exceptions report an
internal error. Resolve the cause before restarting the owner.

Notices are pruned at initialization and when a new notice is created. The owner
keeps an account index for snapshots; neither this index nor historic journal
entries are serialized into the world row. Company removal requires transferring
or retiring its ships first, enforced by the domain and PostgreSQL foreign keys.

Cargo IDs are durable identifiers, separate from catalogue display names.
For example, ID `aluminium_scrap` displays as `Aluminium scrap`. Production
definitions are validated against these IDs at initialization. Perishable
merchant roles remain unsupported and are rejected before the world starts.

New invitation codes use an HMAC subkey derived specifically for invitations.
Existing invitation receipts retain their original code on replay.

Invitation redemption issues the device credential in the form's signed cookie
before the POST. The transaction stores only its hash. If the response is lost,
the same device can repeat redemption and receive the same account credential;
a different device cannot replay it using the invite alone. No extra database
table is needed. Missing cookies, revoked sessions, and expired sessions cannot
use this retry path.

## Cargo identifier migration

`20260908020000_use_cargo_machine_ids.exs` replaces the original cargo IDs with
explicit lowercase snake_case IDs. The generator maps display labels to fixed IDs;
renaming a label must preserve that mapping rather than deriving a new ID.
Ports and company names are outside this migration's scope.

Stop the game server before applying this migration, then restart with the new
code. It updates cargo references in markets, lots, tanker history, instructions,
and journal metadata, plus composite market keys and their holdings. Permanent
lot IDs, lineage, quantities, prices, ledger entries, balances, and command
receipts remain intact. The old and new application versions must not run against
the same database during this upgrade; refresh existing clients after restarting.

The migration takes exclusive table locks and temporarily disables only the lot
immutability and journal sealing triggers within its transaction to rename their
cargo references. Both triggers are restored before commit; a failure rolls back
the entire operation. Foreign keys remain enforced. A rollback reverses the ID
mapping and requires the matching old application code. Historical free-text
notices and receipt fingerprints are preserved, not rewritten.

## Initial instruction schema

The unpublished `20260908000000_add_ship_instructions.exs` creates both
`game_ship_instructions` and `game_visit_plans` in one transaction. The latter
stores an independent onward destination per ship and visit port, including
empty and sell-only visits. It also stores `auto_depart` (default false) and a
nullable departure waiting reason, so the setting and retry status survive
restarts. Production never needs the temporary instruction-only
schema or a visit-plan backfill. The discarded `20260908010000` migration must
not remain in a local database's migration history.

The separate `20260908020000` cargo-ID migration is still required because the
published schema already uses the original cargo IDs. Deploy by stopping the
old game, applying both pending migrations, and starting the updated code.
Existing production cargo and finances are preserved; new instruction and
visit-plan tables start empty.

## Company finance migration

`20260909000000_add_company_finance` adds normalized loans, accrued installments,
operating bills and bankruptcy events. Company rows gain persisted arrears and
closure timestamps. Existing unpaid bills are backfilled at the current world
clock. Principal and interest liabilities reconcile against ledger balances;
installment balances reconcile against their parent loans. Loan proceeds and
principal repayments do not enter operating profit. Bankruptcy write-offs use
receivership equity.

Apply this migration with the game server stopped, using the migration commands
above, then restart it. Do not start a second game process to migrate or seed a
live world. This migration does not rewrite earlier published migrations. Its
rollback is deliberately unsupported once durable finance records exist.

`20260909010000_remove_company_home_port` removes the unused company home-port
column. Starting-port selection only positions the initial fleet; each ship
continues to store its own current port. Historical home ports are discarded.

`20260909020000_accrue_loan_interest_continuously` persists each loan's accrual
clock, fractional-cent carry and interest accrued but not yet due. Existing
loans start accruing at the migration world clock, preserving posted interest.
The ledger reconciles both accrued and due interest; installment rows contain
only due interest. Stop the server before migration and restart afterward.
