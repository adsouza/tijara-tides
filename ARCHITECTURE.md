# Architecture

Tijara Tides carries forward Armchair Metropolist's compiler-enforced layered
architecture, pure domain model, OTP state ownership, PubSub delivery, thin
LiveView UI, and automated checks. This is a multiplayer foundation, not a game
rules proposal.

## Layers

```text
Browser (LiveView JS: render, connection, input transport)
  ↕ HTTP / LiveView WebSocket
TijaraTidesWeb (signed guest session, LiveView, presentation)
  ↓
Infrastructure.WorldServer (authoritative owner, monitored connections, PubSub)
  ↓
UseCases.WorldCommands (command validation/dispatch seam; currently rejects all)
  ↓
Domain.World (pure empty world identity)
```

`boundary` enforces dependencies during compilation. `mix precommit` forces
recompilation with warnings treated as errors, including architectural violations.
The domain purity test carried forward from Armchair Metropolist inspects BEAM
imports for process and framework calls that Boundary alone cannot exclude.

The web layer may call Infrastructure's exported server API. It may not call
use cases or manipulate domain state directly. Future rules belong in Domain and
are orchestrated through UseCases. Infrastructure is where I/O adapters belong.
No speculative gameplay entities or repository ports are supplied yet. The
optional `Infrastructure.Persistence.Repo` provides Ecto/Postgrex connectivity
when `DATABASE_URL` is configured; it does not persist world state yet. See
[database setup](docs/database.md).

## Ownership and synchronization

One supervised `WorldServer` starts with the application and owns the `ocean`
world. It does not start per browser and does not shut down when the last guest
leaves. GenServer calls serialize access. A client cannot submit replacement
state. The command API obtains the guest identity from the calling LiveView's
attachment; client event payloads must never supply trusted identity.

Guest IDs are random, server-minted values stored in signed, HTTP-only session
cookies (secure in production). They identify browser sessions, not accounts.
The public projection contains only the world ID, revision, guest count, and
connection count. It does not expose credentials, process IDs, or private state.

Each connected LiveView attaches once; repeat attachment is idempotent. Each
connection is monitored. Losing one tab does not remove another tab belonging to
the same guest. Guests with no connections disappear from this temporary roster;
future persistent player records must be separate from connection metadata.
Static HTTP rendering never attaches a guest or creates another world.

LiveViews subscribe before attaching and receiving their snapshot. Updates carry
monotonic revisions; stale queued snapshots are ignored. This avoids the initial
read/subscribe race and rolling back the UI with an older event. World-specific
topics isolate updates. For this tiny lobby a complete public projection is cheap;
future gameplay should follow Armchair Metropolist's selective display-diff
approach instead of broadcasting the entire game state to every player.

When enabled, the database repository starts first. The remaining supervision
order is Telemetry → PubSub → WorldServer → Endpoint with
`:rest_for_one`. Losing the world or PubSub restarts downstream services, making
browsers reconnect and mount against the current owner. Revisions reset with an
owner restart, so reconnecting views take a fresh snapshot rather than comparing
it against the old process's revision. This is restart recovery, not durable data
recovery. No shutdown checkpoint or persistence guarantee exists yet.

## Deliberate differences from Armchair Metropolist

- Its per-city Registry/DynamicSupervisor serves independent games. This skeleton
  has one world, started under the application supervisor; a dynamic registry is
  unnecessary until multiple worlds become a requirement.
- Its idle shutdown and local pause behavior do not transfer to a shared world.
  No player can pause, reset, or stop the world in this skeleton.
- Its Tauri/Burrito desktop bundle embeds a local simulation. Here both the browser and
  the Tauri desktop client connect to the remote server, with no local
  authoritative simulation. The desktop client bundles only a connection screen,
  uses native Rust menus for recovery, and grants remote pages no native APIs.
  See [desktop packaging](docs/desktop.md) for macOS, .deb, and Flatpak details.
- Its Postgres/file snapshot adapters and tick scheduler solve established game
  requirements. Storage format, transaction boundaries, tick policy, and offline
  progression remain open until Tijara Tides' design determines them.

## Scope and next decisions

Only a single BEAM node is supported. PubSub does not create distributed state
ownership, and adding replicas would fork the world. There is no cluster discovery
configured. Horizontal scaling needs an explicit ownership/fencing strategy.

Before valuable game state exists, design accounts and authorization, persistence
and migrations, idempotent commands and retries, recovery, and abuse limits.
Choose shared-world rules, time/progression, and visibility before implementing
cities, markets, ships, trade routes, mines, or factories.

Tests cover concurrent clients, same-guest tabs, disconnect cleanup, command
rejection, topic isolation, session reuse, stale updates, and cross-client
LiveView synchronization, and owner/endpoint restart recovery.
CI checks the declared Elixir floor and the local version,
and assembles a production release with assets.
