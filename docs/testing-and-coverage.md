# Testing and coverage

Run `scripts/check-local.sh` for the same local checks used by the pre-push hook.
It selects documentation-only checks when a known range contains exclusively
regular, non-executable Markdown under `docs/`, `README.md` or `ARCHITECTURE.md`.
The fast path checks whitespace, generated documents and `mix test test/docs`,
which may compile normally. It skips forced compilation, the full gameplay and
database suites, coverage, Gettext checks, desktop/Rust checks, asset setup and
release builds. The Git pre-commit formatter already ignores Markdown; use this
fast path for the required validation before committing documentation.

Selection includes every outgoing commit, even changes later reverted, plus
tracked index and working-tree changes. Manual checks use the branch's upstream;
repeat `--base <commit>` for explicit known ranges. Stage new documents first.
Policy files such as `AGENTS.md`, untracked files, unknown/non-ancestor baselines,
new remote branches, non-branch pushes, unusual file modes and empty change sets
require full validation. The pre-push hook checks each remote ref's actual prior
commit and retains its clean-checkout requirement. Use `--full` to run all gates
regardless of scope; do not bypass hooks with `--no-verify`.

Full validation uses disposable PostgreSQL for all Elixir tests and line coverage
and reports desktop JavaScript helper line, branch and function coverage. CI
continues full validation on every push and pull request, uploading reports for
each runtime or platform even when a test or coverage threshold fails.

The [mutation-testing pilot](mutation-testing-pilot.md) records the bounded Muex
experiment and its expansion across finance, trading instructions, commit/replay,
conflict recovery, and persistence failures. It records test improvements and
the baseline and test-selection safeguards required before any mutation-score
gate. Mutation testing remains opt-in.

The [proposed test expansion](test-expansion-plan.md) builds on this policy with
input and notice contracts, lifecycle interactions, SQL transitions, property
tests with shrinking, a shared stateful command fuzzer, generated sequences and
mutation audits across existing code, including earlier finance, queues, markets,
identity and reporting. It records implementation rounds and acceptance criteria.
Review regressions now cover receiving freshness, late auction settlement,
owner-visit coalescing, compiled ship dependencies, persisted-field contracts
and operation counts. The bounded
[gameplay mutation audit](mutation-testing-pilot.md#gameplay-review-regression-audit--2026-10-01)
checks four deliberately broken behaviors. Broader shrinking and generated
state-machine infrastructure remains follow-up work.
Round 1b implements twelve valid web-form variants, two normalization properties
and two real-browser workflows. `LiveViewTest` does not execute browser JavaScript;
SQL-backed form tests alone do not prove serializer coverage. The instruction
metadata/replay regression, checked form inventory, payload properties and
Chromium cohort are implemented. Run `python3 scripts/test-browser.py` after
`MIX_ENV="test" mix assets.build`; it starts its own disposable database and HTTP
server. Install Chromium with `npx playwright install chromium`. Browser artifacts
under `cover/browser-contracts/` contain field names only.

Two checks guard the template-to-handler seam without hand-kept field lists.
`TijaraTides.FormFields` reads every `~H` template and `GameLive.handle_event/3`
clause: each field a submit form, function component inside one, `phx-value-*`
or `JS.push` value sends must be read by that event's handler through its head
pattern, an access, `Map.take/2` or a local helper. Unresolvable names and named
controls outside any submit form raise.

`FormFields.dropped/3` adds the admission dimension. Because `GameLive.run/2`
keeps only fields the submitted action admits, every field a form sends must be
admitted by one of that form's actions or route operations, or be converted by
its handler through a value read; otherwise it would be lost silently. Action
values come from hidden inputs, submit buttons, `phx-value-action` and literal
handler assignments. A value bound from an assign must be declared with the
guard that limits it, and a command form whose action cannot be determined
raises. Command events reach `run/2` or `Game.command/3`, including through
local helpers and delegated event handlers.

Separately, the SQL-backed exchange sweep finds every rendered exchange form,
submits each as rendered in its own world and requires a commit. A further SQL
test withdraws a won luxury consignment through the shared revise form, whose
Withdraw button also sends the revise fields.

The rendered command control sweep (`control_sweep` tag) generalizes both. Its
unit is a control, not an action: a form is identified by the literal prefix of
its template id and the action and route operation a given submit button sends,
and a click by its template id prefix, event, action, operation and
`phx-value-*` keys. Every command form and click producer needs a stable id with
its own literal prefix, and no prefix may be a prefix of another. The required
units come from `FormFields`, so a new button cannot escape the sweep, and two
controls sending the same action are each pressed. Static units track template
coverage; per-unit DOM ordinals retain repeated component instances during
discovery and replay. Entity IDs may differ between fresh worlds, so each replay
selects the same occurrence rather than the first matching template unit.

Legal-command scenarios render every unit, with no exclusions. An exclusion
must record the shortest paths tried: guarantee pledges (an invitee bankrupt
five times) and berth-queue cancellation (a second purchase while loading) were
once excluded as unreachable, and the second hid a duplicate DOM id that
LiveViewTest now reports. Each rendered instance is pressed in every scenario
that renders it enabled, in its own world, through its real control, including
the clicked element's rendered values. Only the inputs a player must supply are
added: blank required fields, the first real option of a required select left
on its placeholder, and a short declared list; an optional select keeps its
empty choice. Disabled controls are skipped because they offer no submission.
Command telemetry must report exactly one commit, and SQL rows must match. A
pair the domain rightly refuses must be declared with its reason; none is.

Pressing each control in every rendering state found forms that could never
succeed there: the add-stop port list defaulting to the loop's own first port,
add-stop offered while next-port instructions block a route, consignment and
exchange sell offered without claimable stock, and bids offered into award
storage. Those forms now offer only values from the domain rules the commands
enforce (`RoutePlans.stop_ports/3`, `instructions_block_route?/3`,
`Warehouse.claimable_stock/3`, `covers?/3`, `receiving_open?/2` and
`reservation_limit/5`), with leases loaded by `WarehouseWorld.hydrate/4` as the
commands load them. Exchange purchases need space for at least one lot; auction
bids need the entire lot. A replacement bid releases its previous capacity claim
before evaluating any receiving warehouse, including shared allocations.
`route_offers_test.exs` and `market_offers_test.exs` show each offered value is
accepted and one more, or any value withheld, is refused.

Submission success alone does not establish the outcome of a deferred command.
`instruction_offers_test.exs` takes the actual next-port defaults through fills
and handling, with fixed boundary witnesses and shrinking properties for cash,
stock, retained cargo, spending caps, buyer funding and whole visit journeys.
It also checks freshness, visit budgets, skipped purchases and owned-stock
selection. A separate property checks current-port Buy defaults across cargo
types. Assertions observe execution quantities and progress, rather than only
comparing query helpers. Deliberate price overrides retain their waiting
semantics.

`instruction_offer_journey_test.exs` submits the rendered quantity, limit price
and spending cap unchanged with tight cash, sails to the purchase port, requires
the entire target to fill, then requires automatic departure after loading. SQL
reload and restart preserve that result. The UI control sweep retains its
submission boundary; this journey adds the deferred outcome boundary.
The sweep also renders a buy-instruction scenario and submits current-port Buy
quantities unchanged, removing its former one-lot override.

CI runs the sweep; local checks do not. `TIJARA_CONTROL_SWEEP_FOCUS` set to
`scenario:id-prefix` renders one scenario and presses only matching units,
without the coverage assertions. The curated `stale-route-cancellation` fault
uses it to show that corrupting the route cancellation ID fails the sweep.
`stale-fleet-queued-cancellation` corrupts only the fleet copy of the queue
cancellation button, proving that repeated instances are submitted
independently. `exchange-capacity-offer` and `auction-capacity-offer` remove the
respective capacity filters and must fail the market offer contracts.

```sh
python3 scripts/test-game-db.py --control-sweep
```

For a focused coverage run:

```sh
python3 scripts/test-game-db.py --cover
npm run desktop:coverage
```

The database script starts and removes an isolated local PostgreSQL cluster. It
removes production database URLs and the local development override from child
environments; it never migrates the deployed or playtest world. Without `--cover`
it runs the same full test suite without instrumentation.

Elixir HTML reports are written to `cover/Elixir.*.html`. The pre-push checks also
save `cover/elixir-summary.txt` and `cover/desktop-summary.txt`. CI artifact names
identify the Elixir/OTP matrix entry or desktop platform. Reports are retained
for 14 days. These generated files remain ignored by Git.

## What the percentages measure

- Elixir uses the built-in `mix test --cover` executable-line metric. The explicit
  project-wide minimum is **90%**; test failures and falling below this threshold
  fail the command and CI. No application modules are filtered out to inflate
  the percentage. The default Mix scope includes compiled test-support modules.
- Elixir **branch/condition coverage is not instrumented**. Hitting an `and`/`or`
  expression's line does not prove each operand or outcome was exercised. The
  scenario matrix below is explicit behavioral evidence, not a branch percentage.
- Node reports actual V8 line, branch and function coverage for modules exercised
  by the desktop tests: currently `desktop/connections.mjs` and
  `desktop/server-url.mjs`. This is not coverage of the browser hooks or the Rust
  desktop application. Those areas have no coverage instrumentation in this setup.

## Required branch and condition tests

New or changed Elixir decisions must have behavioral tests covering every reachable
branch and both outcomes of each independently evaluated condition. This is a
review requirement today; automated branch/condition measurement is not yet
implemented. Passing the 90% line gate does not satisfy this requirement by itself.

- Cover both decision outcomes, including implicit `else` paths, applicable
  `case`/`cond` and function clauses, guard acceptance/rejection, and `with`
  success and failure paths.
- For compound conditions, exercise each operand as true and false when it is
  evaluated, plus short-circuit paths. A skipped operand is not a false outcome.
  For `a and b`, use `(false, skipped)`, `(true, false)`, and `(true, true)`;
  for `a or b`, use `(true, skipped)`, `(false, true)`, and `(false, false)`.
  For truthy operators (`&&`/`||`), preserve and test their value-returning
  semantics, including relevant `nil`/`false` inputs.
- Assert observable results and state effects, not merely successful execution.
  For rejected operations, check that protected state remains unchanged. For
  numeric decisions, include values below, at, and above relevant boundaries.
- In the PR, map changed decisions to named tests. Explain infeasible outcomes
  with the invariant that makes them unreachable; do not silently omit them.
  Changes without Elixir decisions can mark this requirement not applicable.

Branch coverage and condition coverage are separate requirements. Neither implies
all combinations or paths have been tested, nor does this policy claim MC/DC.
Mutation testing complements these tests by checking whether deliberately wrong
behavior is detected; a mutation score is not a branch or condition percentage.

### Stateful change review checklist

Apply this checklist now to stateful changes, including work landing alongside
the [test expansion](test-expansion-plan.md#round-0-review-checklist). Each review
must answer:

1. What decisions and input boundaries changed, and which named tests cover
   them? Which outcomes are infeasible, and why?
2. Which resources are acquired, consumed, transferred and released on every
   exit path? Which inbound or committed obligations must remain?
3. Which lifecycle phases, timers and clocks interact, and what reachable
   sequence exercises them?
4. Which SQL constraints and write order apply? What happens on replay,
   restart and publication?
5. What independent oracle checks the result, and which semantic fault would
   it catch?

The checklist is a current review requirement. Completed examples map its five
questions to [input and notice contracts](test-discovery-matrix.md#round-1b-evidence),
[resource lifetimes](test-discovery-matrix.md#round-4-executed-cohort),
[phase and clock boundaries](test-discovery-matrix.md#round-2-audit-and-evidence),
[SQL ordering and recovery](test-discovery-matrix.md#round-3-sql-evidence-and-constraint-inventory)
and the [fault detection matrix](test-discovery-matrix.md#round-5-detection-matrix).
These examples do not replace the answers for a new change or supply automated
branch/condition measurement.

### Automated measurement acceptance criteria

An automated gate remains required follow-up work. Before enabling it:

1. Validate instrumentation on both CI Elixir/OTP combinations using fixtures
   with known missed branches and conditions, including same-line expressions,
   guards, pattern clauses, implicit alternatives, and short-circuit evaluation.
   Verify that instrumented and ordinary execution preserve the same semantics.
2. Report branch and condition metrics separately, with source locations and an
   explicit inventory of unsupported constructs. Missing instrumentation or
   reports must not count as covered; scoped results must identify their scope.
3. Establish the existing-code baseline and enforce complete coverage of feasible
   outcomes in new or changed decisions, with reviewed, documented exceptions.
   Ratchet existing coverage without silently lowering the baseline.
4. Run the same gate locally and in CI, include the disposable PostgreSQL tests,
   and upload diagnostic reports even when the gate fails.

The current [Erlang `cover` API](https://www.erlang.org/doc/apps/tools/cover.html)
counts executable lines. Its clause-level coverage analysis still aggregates
line counts; it does not establish full branch or condition coverage.
[ExCoveralls](https://github.com/parroty/excoveralls) uses Erlang `cover`, so
installing it alone does not implement this gate.

## Instruction branch scenarios

The named cases in
`test/tijara_tides/domain/ship_instructions_test.exs` exercise these conditions.
Every resource-wait case asserts zero fills, unchanged cash/cargo/markets/lot
allocation/journal, no repeated notice on unchanged retries, and exactly one
fill after its blocking condition clears.

| Decision | Exercised cases |
|---|---|
| Cargo and liquidity | Missing cargo, zero supply, zero demand, insufficient buyer budget; each resumes when restored |
| Available company funds | No cash, cash already reserved, unpaid costs; each resumes when restored |
| Onward voyage | Purchase affordable but onward voyage unaffordable; missing onward route; both resume when restored |
| Market eligibility | Previously configured market becomes unsupported; resumes after eligibility is restored |
| Price and spending | Price below buy limit requirement; spending cap too small; neither settles |
| Partial fills | Available supply fills part of a target; handling blocks a duplicate; later supply fills only the remainder |
| Handling order | Sales settle and unload before buying; capacity remains unavailable during handling |
| Capacity exhaustion | Cancel loading shortfall when no sales remain; preserve it when a pending sale could free space |
| Ownership and configuration | Missing/foreign ship, invalid/current visit port, incorrect sailing destination, incompatible/unknown/non-manual cargo, missing market |
| Numeric validation | Non-integer and out-of-range quantities/prices/budgets, invalid onward port |
| Lifecycle limits | Twenty active instructions accepted, twenty-first rejected, cancellation frees a slot, repeated/missing cancellation rejected |
| Instruction expiry | Unlimited and legacy rows, duration types/bounds, ownership fencing, before/at deadline, newly viable fills, at-sea expiry, queued berth admission, partial fills and committed handling, automatic departure after handling, unchanged terminal records and retry notices |
| Minimum shelf life | Numeric bounds and defaults, exact qualifying boundary, wait without cash/cargo movement, later replenishment, partial fills, earliest qualifying expiry, retained excluded lots/cost/split lineage, reservation protection, owned-stock berth admission, qualifying cargo aboard, maximum targets waiting and immutable current-visit snapshots |
| Departure and privacy | Cancel waiting remainders and incompatible plans; owner-only visibility |

The database/LiveView integration test additionally exercises UI submission and
preserved drafts, command replay, cancellation, automatic arrival settlement,
SQL reload and a single financial posting after restart.
The instruction-expiry integration case covers optional/invalid form input,
tick-preserved drafts, private countdowns, SQL deadlines, replay without extending
the deadline, restart without offline catch-up, terminal history and no duplicate
expiry notice or financial posting.
The freshness form integration case covers preserved drafts, invalid input,
stored instruction and route terms, route edits/clearing, owner-only visibility,
SQL reload and creation replay. Root codec cases cover legacy defaults and
rejection of invalid freshness terms.

## Server failure scenarios

Repeating-route maximum waits are covered by named cases in
`test/tijara_tides/domain/ship_routes_test.exs`: limit ownership and bounds;
the inclusive deadline versus newly fillable targets; partial loading and
unstarted purchases during unloading; actual arrival on coarse ticks; berth
retries and pause/resume; completed targets awaiting departure; and
stop-after-visit with a fresh next-circuit deadline. Codec tests cover legacy
unlimited rows and invalid timer shapes. The database integration case covers
the wait form, private countdown/shortfalls, receipts and restart before and
after timeout. The early simulation phase is checked by phase telemetry tests.

`test/tijara_tides/infrastructure/game_server_failures_test.exs` uses narrow
persistence doubles at existing callback boundaries. It verifies rejected startup
commits, startup connection exceptions, command storage versus domain exceptions,
rejected tick commits, simulation exceptions, and invalid-session connections.
Failures preserve the last game/projection, stop progression, avoid publishing an
uncommitted revision, and omit private exception messages from logs.

`test/tijara_tides/infrastructure/game_persistence_test.exs` also fences a live
owner using a real PostgreSQL epoch change. Its subsequent tick cannot advance
stored clock/revision or publish a change. Existing transaction rollback and
ledger tests cover failures inside the SQL unit of work.

### Stateful discovery and replay

The shared runner in `test/support/command_fuzzer/` checks symbolic action
preconditions against a small independent model before resolving identities.
Removing a creator during shrinking skips its now-invalid dependents. Assertions,
model-valid rejections, internal errors and unexpected halts always propagate.
Progress prefixes remain outside the shrinkable suffix and count inside the
trace budget. The command/route/form inventories fail on unclassified additions.

Ordinary checks run the four lifecycle properties and broad command property;
the disposable database suite also runs the four SQL properties and fixed
receipt/restart traces. SQL servers belong to individual cases and shrink
attempts, never to property-level `setup`. Failure cleanup is exercised directly.
The constructor clock/valuation seams keep SQL ticks reproducible without sleeps.

For the bounded optional sweep and corpus replay:

```sh
TIJARA_FUZZ_EXTENDED=1 TIJARA_FUZZ_CORPUS=1 mix test test/tijara_tides/use_cases/extended_fuzzer_test.exs --seed 12345
```

This runs 100 cases with at most 60 actions and 100 shrink steps; corpus admission
is capped at 50 versioned records. Failure diagnostics are written before
reraising under `cover/property-failures/<family>/<case>/`. Preserve the original
and final failing traces; replay the final input to identify its invariant before
promoting it to a checked-in regression. Runner sensitivity fixtures are labelled
separately from confirmed production defects. See the
[executed discovery matrix](test-discovery-matrix.md#round-4-executed-cohort) for
milestones, exclusions and measured evidence.

Command admission schemas are checked against the complete dispatch and route
operation inventory. Table tests reject unknown, atom and misplaced keys for
every variant; bounded properties mutate extra fields and retry the corrected
request. SQL tests check unchanged rows, revision and receipts on rejection,
including a retry after restart. Complete instruction, exchange and route
payloads exercise the size ceiling with all optional terms together. Company
names at 120 code points exercise default hull purchases and suffix collisions;
migration tests verify both refusal of legacy oversized names and SQL caps.

### Bounded mutation audit

The opt-in runner applies exact curated patches only in disposable copies and
uses Muex 0.11.2 operators in a separate tool project. The application dependency
list and lock stay unchanged. Curated batches contain at most twelve patches;
generated audits contain at most twenty candidates per source and sixty total.
One worker compiles each mutant within 120 seconds, then tests it with seed 12345
and a 30-second limit. Baselines, restoration and full-applicable survivor triage
are separate checks with a 120-second limit; they do not increase the detection
count by themselves. Replays require an explicit `--start` index.

```sh
python3 scripts/mutation-audit.py curated --start 0 --count 12 --out cover/mutation-audit/curated-0
python3 scripts/mutation-audit.py curated --start 12 --count 12 --out cover/mutation-audit/curated-12
python3 scripts/mutation-audit.py curated --start 24 --count 12 --out cover/mutation-audit/curated-24
python3 scripts/mutation-audit.py generated --out cover/mutation-audit/generated
python3 scripts/mutation-audit.py replay --report cover/mutation-audit/generated/generated.json --start 24 --extra-test test/tijara_tides/domain/market_quote_properties_test.exs --out cover/mutation-audit/replay-24
```

Generated selection is explicit and includes indirect callers and properties;
it bypasses Muex's dependency-selection heuristic. Exact canonical source,
mutant source, patches, provenance, runtime and failing tests are retained.
Canonical unmutated baselines prove AST rendering did not itself break the
selection. A survivor receives the same source patch in the full applicable
scope, including SQL; selection misses remain distinct from missing assertions.
Replays verify the original source hash and exact patch hash before testing.

Compile errors, fixture/startup failures, timeouts and harness failures never
count as detections. `scripts/test-mutation-audit.py` checks that classification
contract in local full checks and CI against logs from real `mix compile` and
`mix test` runs in a throwaway project, including `setup` and `setup_all`
crashes and a timeout, and checks the command-line range and provenance
refusals. Inspect each detecting assertion before recording it in the discovery
matrix. Operator generation is deliberately bounded and excludes no unproven
survivor as “equivalent.” The [mutation audit report](mutation-audit.md) records
the selected sample and gaps.
