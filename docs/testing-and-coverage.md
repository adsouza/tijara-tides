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
Round 1b also specifies valid web-form contracts, normalization properties and
two real-browser workflows. `LiveViewTest` does not execute browser JavaScript;
SQL-backed form tests alone do not prove serializer coverage. The instruction
metadata/replay regression is implemented; the broader form inventory, properties
and Chromium cohort remain proposed in the expansion plan.

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

The checklist is a current review requirement. Links to the expansion's completed
detection matrix will be added in Round 5; that does not delay its use. This
documentation does not supply automated branch or condition measurement.

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
