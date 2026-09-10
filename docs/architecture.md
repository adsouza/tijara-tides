# Domain boundaries and command/query architecture

Tijara Tides is a modular monolith with a pure domain, a transport-independent
application layer, PostgreSQL adapters, and Phoenix LiveView presentation. One
GenServer remains the authoritative writer for each running world. The world is
the current transaction boundary; the modules below are responsibility boundaries,
not independently deployed services or independently committed aggregates.

## Responsibilities

| Area | Owner | Invariants |
|---|---|---|
| Identity and company formation | `Domain.Accounts` | Valid durable sessions; one active company per account; invitation entitlement lifecycle; zero-asset formation and explicit borrowing. |
| Repeating routes | `Domain.ShipRoutes` | Private bounded stop templates; durable visit cursor and phase; fresh load shortfalls per visit; pause without cancelling committed movement. |
| Ship operation | `Domain.Fleet` | Ownership and handling status before departure; fuel funding and reservation; capacity measured in kg/litres; fuel and crew costs settled once. |
| Cargo | `Domain.CargoRules`, `CargoLots` | Hold compatibility, liquid mixing restrictions, freshness, stable lot identity and split lineage. |
| Trading | `Domain.Trading` | Atomic cash, cargo, liquidity and accounting changes; destination funding rechecked before purchase. |
| City markets | `Domain.Markets` | Bounded stock, demand and budgets; finite manufactured stock; no synthetic merchant inventory; world-time replenishment. |
| Credit and insolvency | `Domain.Finance` | Fixed loan terms, oldest-due settlement, protected reservations, shared active-clock arrears, bankruptcy and replacement entitlement. |
| Accounting | `Domain.Journal`, persistence ledger adapter | Balanced integer-cent entries; durable ledger and entity balances committed together and reconciled. |
| Financial accumulation | `Domain.Reporting`, `UseCases.CommitPreparation` | Integer capital-time integration and accounting categories; apply pending journal events before commit, clear only after success. |
| Visibility | `Domain.Visibility` | Public ships never expose cargo, balances, credentials or private instructions; owner projections require authentication. |
| Clock orchestration | `Domain.Simulation` | Advance the supplied clock once, settle finance before and after fleet operations, then market recovery, ship instructions and invitation expiry in the established order; commit all phases together. |

`Domain.ReadState` exports only reads for application projections.
`Domain.State` is unexported internal state-access machinery, not a general
application write API. The compatibility facade exposes no generic put/delete
operations; sign-out goes through `Accounts.sign_out/2`. A change to an entity belongs in the domain operation that owns its
rules. A row or map is not automatically a DDD aggregate.

`Domain.Trade` is an explicit trade intention; execution still validates its
values against current state. `Domain.Capacity` is an occupied-capacity value.
Durable entities retain their existing string-keyed representation behind the
relational mapper to preserve stored data and wire compatibility. New types do
not authorize bypassing ownership, funding or lifecycle checks.

`Domain.Game` remains a compatibility facade. New rules belong to the focused
modules, not that facade. These responsibilities can guide future bounded-context
design, but trading and fleet are not independent contexts: they currently
participate in shared synchronous invariants.

## Command execution and atomicity

```mermaid
flowchart LR
  UI[LiveView or another transport] --> Adapter[GameServer adapter]
  Adapter --> Workflow[UseCases.GameCommands]
  Workflow --> Rules[Pure domain operation]
  Workflow --> Port[UseCases.CommandStore port]
  Port --> SQL[PostgreSQL adapter]
  SQL --> Commit[Atomic commit]
  Commit --> Projection[Committed read projection]
  Projection --> Notify[Revision publication and reply]
```

The adapter supplies credentials, time, identifiers and persistence context.
`CommandRequest` carries the original payload, request ID and fingerprint.
`GameCommands.run` authenticates the session, validates the payload, checks the
durable receipt, invokes
the domain operation, and commits changed state with its receipt and accounting.
The persistence adapter wraps the existing `GameStore` transaction rather than
introducing a second transaction around it.

The SQL transaction locks the world row and checks the ownership epoch. It writes
changed rows, lot records, journal entries, the command receipt and world metadata
together. No successful command acknowledgement or revision publication precedes
that commit.

Invalid or expired sessions return `:invalid_session`; non-map payloads return
`:invalid_command_payload`, payloads over 12 keys return
`:too_many_command_fields`, and payloads over 4096 encoded bytes return
`:command_payload_too_large`. These validation errors do not touch persistence.

A business rejection leaves the current state available and unchanged. A commit
failure stops normal world operation; an unexpected storage or domain exception
is classified by the adapter and also stops the world. A retry with the same
request and fingerprint returns the stored result; conflicting payload reuse
fails. Both the initial receipt check and a receipt discovered inside the
transaction use the same result-decoration path. Plaintext invitation credentials
remain outside durable receipts.

`CommandResult.committed?` distinguishes new commits from replay, so replay does
not increment the revision or publish a fictitious change. Seed, redemption,
sign-out and simulation progression retain their established lifecycle handlers
and share the same commit-before-publication discipline.

Before splitting world transactions into smaller aggregates, explicitly resolve
cross-company trades, liquidity competition, cargo ownership and financial
conservation. A process-per-ship split alone would not solve those invariants.

## Query responsibilities and consistency

`UseCases.GameQueries` owns pure planning and display-data calculations:
destination comparisons, affordable trade limits, purchase estimates, cargo
market rows and ROI ordering, port cargo visibility, and consolidated/sorted
manifests. The infrastructure read adapter supplies the loaded catalogue.
LiveView owns selections, menus, formatting and layout, not these calculations.

`WorldProjection` is a typed public read model containing the map/public world
and market quotes for one committed revision. It is built on startup and replaced
after a successful state commit, before publication. Multiple snapshots reuse it.
A failed transaction never replaces it. The projection is disposable and is
rebuilt from authoritative state after restart; it is not a second source of truth.

Private projections are built only after validating the requesting session
against current state and wall-clock expiry. They are not stored in the shared
public projection. Query helpers consume the appropriate projection; filtering
in JavaScript or LiveView is not a privacy boundary.

Snapshots and voyage previews still execute through the owning GenServer. This
retains ordered, current reads without a second process, separate database or
eventual-consistency protocol. UI-side pure query transformations run outside
that mailbox. If load warrants independently served reads later, their access
control, revision consistency and failure behavior need explicit tests first.

This is lightweight CQRS with distinct command workflows and read projections.
It is not event sourcing: PostgreSQL entity state is authoritative, and the
financial ledger is accounting history rather than a replay log for all gameplay.

## Financial report reads and writes

`Journal` emits balanced accounting events without calling reporting code.
`CommitPreparation` applies their financial effects and accrues period totals
for commands, simulation, and lifecycle writes before the shared transaction.
Only a successful commit clears events and compacts closed report periods.

`ReportQueries` owns period selection, retention, eligibility and public-field
policy. Its `ReportStore` port is implemented by the PostgreSQL adapter. Queries
read one selected period in pages of at most 10 rows per list, apply owner scoping
in SQL, and verify world epoch/revision/clock in a read-only repeatable-read
transaction. Revision races re-plan and retry at most twice. SQL runs in the requesting
process after the world owner authenticates and prepares the query, leaving the
world mailbox free. Owner history has independent pagination.
Archived summaries stay in relational storage; only current quarter
and year accumulators are restored into world memory. Compaction never deletes
archived database rows.

The financial panel renders a prepared page. It requests data on opening, changing
selection, paging or explicit refresh; ordinary world ticks do not reload history.
A report read failure leaves gameplay available and offers a retry. The ledger
and summaries remain atomically committed; this is CQRS, not event sourcing.

## Change and verification rules

- Domain code cannot depend on processes, storage, transport or wall-clock access;
  the strict `Boundary` configuration enforces dependency separation.
- Application workflows depend on domain rules and persistence ports, not Ecto
  or Phoenix. Infrastructure implements those ports.
- Preserve command fingerprints and durable receipt results across refactors.
- Put economic estimates beside the domain rules they reuse or in pure query
  projections; presentation formats the result.
- Prove atomicity, replay, failure behavior and privacy with tests, not only module
  naming. Existing PostgreSQL tests cover conservation, rollback, owner fencing,
  restart recovery and request replay. Workflow tests inject both replay paths and
  commit failures; browser tests cover the query-driven UI.
- This refactor needs no SQL migration, data reset or gameplay rebalance. Existing
  startup ownership fencing and deployment procedures remain applicable.

## Single-visit ship instructions

`Domain.ShipInstructions` owns private next-visit plans, partial-fill progress,
spending caps and cancellation. `Domain.Commands` dispatches creation and
cancellation through the existing receipt-protected command workflow. Successful
manual departure cancels waiting remainders and incompatible destination plans.
Simulation attempts instructions after fleet handling and market replenishment,
using the same `Trading.execute` operation as manual trades. A tick commits fills,
lot identities, ledger postings, instruction progress and notices together before
publication. Failed quantity probes are discarded pure state values.

`game_ship_instructions` stores typed relational rows with ship, company, cargo
and port references. Apply migration `20260908000000` before running this code.
Only authenticated owner projections include these rows. There are no separate
order timers or offline catch-up: retries use the existing suspended world clock.

`game_visit_plans` stores one private onward plan per ship/port visit independently
of cargo orders, enabling empty and sell-only legs. Both tables are created by
the initial instruction migration `20260908000000`; no intermediate instruction
schema is deployed. Conflicting instructions stay paused until explicitly
resolved. `instruction_onward` creates or updates the visit plan and its
outstanding buy instructions in one command transaction.
A successful departure consumes the current visit plan and removes plans for a
different next destination. Arrival suggests the saved onward leg in the UI;
manual departure remains the default. Visit plans persist `auto_depart` and a
waiting reason. After processing all cargo instructions, the same simulation tick
calls `Fleet.sail` for opted-in docked ships whose visit orders are filled or
cancelled. Handling, route availability, unpaid costs and fuel/canal funding still
apply. Departure, plan consumption, ledger entries and notices commit together;
failed persistence cannot publish or retain a departure. Failed departure checks
keep the plan for retry and emit a notice only when the reason changes. No cash
or cargo moves merely by saving a plan.

Container startup migrates configured storage before booting the supervision
tree. `Release` coordinates `Ecto.Migrator` through `SchemaMaintenance`: schema
changes serialize with world claims and fence earlier world epochs. Migration
failure prevents startup; migration-free restarts do not change world epochs
until the normal world claim.

## Repeating route orchestration

`ShipRoutes` validates private route templates and materializes one visit at a
time into `ShipInstructions`. Sale instructions finish before loading targets
are evaluated against retained cargo. The existing trading and fleet operations
remain responsible for cash, cargo, handling and departure invariants.
`ShipInstructions.depart` advances the route only after a successful departure;
failed commits cannot publish a new cursor. Paused routes emit no new fills or
automatic departures. Bankruptcy removes route configuration and pending visits.

`game_ship_routes`, `game_route_stops` and `game_route_rules` are typed relational
tables with foreign keys and bounded positions/quantities. They use the existing
fenced transaction and command receipt workflow. `GameQueries.route_editor`
prepares the owner-only editor model; the component formats it. No public world
projection contains route cargo targets, limits or budgets.

### Exception diagnostics

Caught server exceptions use Infrastructure.ExceptionLog to record their type,
message, and stack trace. Do not substitute a type-only or generic failure log.
The formatter redacts common credential formats, database row details, and
embedded values in pattern-matching exceptions; stack frames retain arity rather
than argument values. Never deliberately include credentials or request bodies
in exception messages. Process-exit payloads remain summarized because they can
contain complete GenServer requests. Expected validation failures remain normal
error results rather than exceptions.
