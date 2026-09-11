# Architecture

Tijara Tides carries forward Armchair Metropolist's compiler-enforced layered
architecture, pure domain model, OTP state ownership, PubSub delivery, thin
LiveView UI, and automated checks. This is a multiplayer foundation, not a game
rules proposal.

## Layers

The authoritative module responsibilities, transaction invariants, and CQRS
contracts live in [domain boundaries and command/query architecture](docs/architecture.md).
This entry point provides the dependency overview and operating context; update
the linked specification when changing those contracts.

```text
Browser / native webview
  → TijaraTidesWeb.GameLive and GameSessionController
  → Infrastructure.GameServer (transport and world ownership)
  → UseCases.GameCommands (authenticated command workflow)
  → Domain.Commands → Domain.Accounts / Domain.Trading / Domain.Fleet

UseCases.GameCommands → UseCases.CommandStore (persistence port)
Infrastructure.Persistence.CommandStore implements UseCases.CommandStore
  → Infrastructure.Persistence.GameStore (atomic PostgreSQL transaction)

Infrastructure.GameQueries → UseCases.GameQueries (pure read calculations)
Infrastructure.GameServer → UseCases.WorldProjection (committed public cache)
```

The application depends on the persistence port; the infrastructure adapter
implements it. Application code has no dependency on the PostgreSQL adapter.
`Domain.Game` is a compatibility facade, not a home for new rules.

`boundary` enforces dependencies during compilation. The domain purity test
inspects BEAM imports for process and framework calls. Domain operations receive
explicit time, identifiers, and static catalogue data; they perform no I/O.
`Domain.ReadState` exposes reads across the boundary; `Domain.State` mutators
remain internal, with no generic mutation delegates on the public facade.
Infrastructure owns PostgreSQL, credential hashing, scheduling, and publication.
`WorldServer` tracks temporary browser presence for authenticated play views;
the home page subscribes to its public count without registering itself.
Play views attach by browser guest identity after an authenticated snapshot,
detach when authentication is lost, and are removed on process termination.
This roster remains separate from durable gameplay state.

## Ownership and synchronization

One `GameServer` owns the durable ocean world. Startup increments a database
ownership epoch, restores entities and the committed simulation clock, and leaves
progression paused until an authenticated client connects. Five-second ticks
continue while the server stays awake after disconnect. Restart adds no elapsed
wall time. Database failures stop progression and commands rather than producing
uncommitted results.

PostgreSQL stores typed relational tables for accounts, companies, ships,
markets, sessions, invitations, and notices. Ship cargo and perishable market
stock use permanent lot identities and separate ordered location rows; foreign keys enforce ownership and catalogue
references. `GameRows` maps these records to the pure domain model. Each
transaction locks the world row, verifies the owner epoch, writes changed
columns and batches, and records the account/request fingerprint and result.
Only variable command-result receipts retain JSONB. Pure domain operations emit
balanced journal events and new lot identities alongside state changes. The
same transaction persists these, verifies ledger reconciliation, and writes the
receipt. Pending events are cleared after commit; historical journals and lot
lineage stay in PostgreSQL rather than accumulating in world-process memory.
Startup audits ledger totals before serving gameplay.
A superseded process cannot commit. Same-request retries replay the committed
result; a changed payload under the same request ID is rejected. Publication and
acknowledgement follow commit. Keep one server instance; fencing is overlap
protection, not a multi-instance availability mechanism.

Accounts outlive browser connections. Invitations are single-use and only their
hashes are stored. A signed, HTTP-only cookie carries an opaque random device
credential; server-side session lookup and expiry authorize every command. The
anonymous invitation form pre-issues that private credential before any
redemption mutation. Redemption retries match both the invitation's account and
the existing device session, without creating another account or extending its
expiry. A revoked session cannot be recreated by retrying the invitation.

Pre-issuing moves that credential into the browser before it authorizes
anything, so its exposure begins at the form rather than at the redemption
response. The window is longer, not the capability: the value is inert until an
invitation is redeemed with it, it travels in the same signed, HTTP-only,
SameSite=Lax cookie as the session it becomes, and reading it before redemption
grants what reading it afterwards would. Minting on POST would shorten that
window and restore the unrecoverable lost-response failure pre-issuing exists to
prevent.

Public projections omit balances and cargo. PubSub announces revisions only;
subscribers fetch their own authorized projection. Static route and map data are
versioned assets. Email identity linking is implemented; Google linking remains
unimplemented. Financial report pages use the application report-query port,
with owner filtering and bounded pagination in PostgreSQL. Only current report
accumulators occupy world memory. See [domain and CQRS architecture](docs/architecture.md)
for commit preparation and query consistency.

When enabled, Repo and Readiness start before Telemetry, PubSub, WorldServer,
GameServer, and Endpoint under `rest_for_one`. Owner crashes restart Endpoint so
clients reconnect. Storage failure leaves gameplay unavailable and `/statusz`
unhealthy; restart after repairing the failure. Configured storage is migrated before the supervision tree starts; migration
failure prevents startup.

See [implementation scope](docs/IMPLEMENTATION.md) and
[database operations](docs/database.md) for playtest rules and verification.

## Deliberate differences from Armchair Metropolist

- Its per-city Registry/DynamicSupervisor serves independent games. This skeleton
  has one world, started under the application supervisor; a dynamic registry is
  unnecessary until multiple worlds become a requirement.
- Players cannot manually pause, reset, or stop the shared world. Future
  simulation continues while the server remains awake, including the idle
  interval after the last player disconnects. Hosting suspension or outages
  pause it globally; it resumes without catch-up when a player returns.
- Its Tauri/Burrito desktop bundle embeds a local simulation. Here both the browser and
  the Tauri desktop client connect to the remote server, with no local
  authoritative simulation. The desktop client bundles only a connection screen,
  uses native Rust menus for recovery, and grants remote pages no native APIs.
  See [desktop packaging](docs/desktop.md) for macOS, .deb, and Flatpak details.
- Its Postgres/file snapshot adapters solve a different persistence model. Tijara
  Tides commits individual entity changes with command receipts and a fenced
  shared-world clock.

## Verification

Tests cover the original guest lobby, company and trade rules, privacy, voyage
bounds, concurrent invitation redemption, retry conflicts, transaction rollback,
ownership fencing, restart recovery, and a complete LiveView trade journey.
CI checks both supported Elixir/OTP pairs, disposable PostgreSQL integration,
generated catalogue consistency, assets, and a production release.

The Ship aggregate now owns hull/hold transitions and route/visit lifecycle;
Fleet and Trading coordinate economic settlement through its operations. See
[the aggregate migration](docs/architecture.md#ship-aggregate-migration) for
ownership, compatibility adapters, and remaining extraction work.

Company balances and accounting entries are now applied together by the
`CompanyFinance` root. See [company finance aggregate](docs/architecture.md#company-finance-aggregate)
for ownership, settlement and the retained world transaction boundary.
