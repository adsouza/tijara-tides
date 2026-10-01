# Proposed test expansion

Status: proposal for implementation in five rounds, with a verified commit after
each round. This document does not add tests or change game behavior.

## Goal and current evidence

Catch the classes of failure behind the recent preset, notification, departure
funding, visit-budget and receivership defects, including nearby combinations
that the individual regression tests do not cover.

The repository already has substantial relevant coverage:

- [Testing policy](testing-and-coverage.md) requires branches, conditions,
  boundaries and protected-state checks, but branch/condition measurement is
  still a manual review requirement. The 90% Elixir gate measures lines.
- [Generated workflows](../test/tijara_tides/domain/generated_workflows_test.exs)
  exercise eight fixed seeds of 90 actions and check progress, capacity and
  accounting. Their actions are lumber trades, manual sailing, cancellation and
  ticks; they do not generate route edits, funding policies or liquidation.
- [Persistence tests](../test/tijara_tides/infrastructure/game_persistence_test.exs)
  already exercise real PostgreSQL constraints, replay, restart and rollback.
  [Batching tests](../test/tijara_tides/infrastructure/persistence/game_rows_batching_test.exs)
  use a counting double, which cannot enforce SQL constraints.
- The recent fixes have focused regressions. Retain and extend them; do not
  replace them with randomized tests.
- The [mutation pilot](mutation-testing-pilot.md) already covers several economic
  and persistence paths. It also identified a test-selection miss, so a generated
  mutation score alone is insufficient evidence.

The priority is stronger contracts and sequences, followed by generated
exploration. Increasing the line-coverage threshold is not the proposed remedy.

## How property and mutation testing fit

Use both throughout the rounds. Property tests express rules over generated
inputs and sequences; shrinking helps produce a smaller failing example.
Mutation tests deliberately break a rule to check whether the assertions detect
it. Named regressions preserve previously discovered counterexamples.

Add **StreamData with ExUnitProperties** as a test-only dependency in Round 1,
locking the selected release and checking both existing CI runtime combinations.
Its [official documentation](https://stream-data.hexdocs.pm/ExUnitProperties.html)
describes generated checks, shrinking, seed replay and run/shrink limits.
Keep the existing seeded trading workflows; supplement them with properties.
StreamData supplies data generation and shrinking; the small state model and
dependency-aware lifecycle runner described below are repository test code.

Continue the existing **Muex** audit, initially pinned to the pilot's 0.11.2
release in an isolated test environment. Use generated operator mutations as
well as curated fault patches; generic operators will not necessarily recreate
a missing visit release or an incorrect SQL write order. The
[Muex documentation](https://muex.hexdocs.pm/readme.html) describes its mutators
and scoped execution. Revalidate selection and baseline behavior for the pinned
version rather than assuming the tool fixes the pilot's observed selection miss.

| Property family | Generated variation | Oracle |
|---|---|---|
| Validation and ownership | Constructed valid names, injected forbidden characters, boundary lengths, typed references and account ownership | Expected admission/error from the declared contract; unchanged protected state on rejection |
| Row codecs | Valid typed budgets, requests and pools, including optional fields and boundary values | Decode/encode preserves semantic fields; hand-authored row expectations prevent two matching codec mistakes from passing |
| Budget conservation | Valid reserve/consume/resize/release sequences | Initial allocation plus net adjustments equals purchases plus released and remaining funds; visit identity stays correct |
| Funding lifecycle | Waiting ages, available cash, policies, zero/partial windows and deadline offsets | One active accumulator; fixed deadline; no double reservation; oldest eligible allocation under fixture rules |
| Liquidation lifecycle | Occupancy, charges, proceeds, deadline offsets and estate-cover attempts | Occupancy cannot grow during liquidation; cover does not revive the lease; proceeds/charges reconcile once |
| Persistence transitions | Equivalent handoffs with different IDs and insertion orders | Every valid transition commits; invalid claims roll back; reload preserves authoritative state |

Generate valid cases by construction and invalid cases by a deliberate violation
of one rule. Bias toward boundaries and interactions, with explicit examples
ensuring each critical category runs; probability alone cannot guarantee coverage.
Use separate rejection generators with known expected errors. Avoid filtering
arbitrary maps until they happen to look like a valid game state. StreamData's
[generator documentation](https://stream-data.hexdocs.pm/StreamData.html#filter/3)
also cautions against excessively narrow filters.

Treat two independent implementations agreeing as supporting evidence, not a
complete oracle. Pure-versus-SQL checks need independent expectations for the
affected reservation, deadline or identity. Codec round trips alone cannot
detect two sides dropping the same field.

## Contracts to assert

Build small test-side assertions from the design's
[gameplay invariants](DESIGN.md#15-implementation-boundary-and-invariants).
Expected values must come from fixture facts and explicit rules, rather than
calling the production predicate whose behavior the test is checking.

| Contract | Required evidence |
|---|---|
| Input admission | Representative accepted payloads commit and reload; invalid payloads return the specified error before writing or publishing |
| Identity and ownership | Creation uses an allocated identity; editing requires an existing owned identity, according to each command's contract |
| Reservation lifetime | A stop budget belongs to the selected visit, including its inbound voyage; ending that visit releases only its unused funds |
| Funding exclusivity | At most one departure request per company has an active accumulation window, including a zero-balance window; accumulated funds cannot also fund another departure |
| Irreversible liquidation | While a pool is active, receiver cover cannot extend its source lease; legitimate release/resize operations preserve the shrinking-allocation rule |
| Exactly-once effects | Retry, receipt replay, restart and repeated processing of the same transition do not duplicate settlement, release, charges or transition notices |
| Atomic persistence | A valid transition commits under actual constraints; a failed commit leaves rows, receipts, ledger and published state consistent with the last committed revision |
| Presentation contract | A current domain-produced notice reaches the intended renderer variant with its required values in both supported locales |

Scope accounting assertions carefully. The generated trading test's inventory
equals cargo aboard only because that fixture has no warehouse inventory. New
warehouse/estate scenarios must include their holdings. Reservation checks must
inventory the applicable sources, including fuel, orders, bids, liquidation
proceeds, visit budgets and accumulation. Where that inventory is incomplete,
assert the affected reservation delta rather than claiming total equality.
Use `FinancialLedger.audit/2` as an additional durable check, not the sole oracle:
its reservation check is a lower bound and does not establish visit identity.

## Round 1: Input and notification contracts

Extend the current preset regressions into table-driven contract tests, starting
with presets and then company/ship names and player-supplied entity references.
Reuse data tables where rules are shared; keep command-specific expected errors
and identity semantics explicit.

Primary targets: `graded_books_test.exs`, `localization_test.exs`,
`use_cases/game_commands_test.exs`, and focused database contract tests.
Add test-side generators under `test/support` and properties for the typed
`VisitBudget`, `DepartureRequest` and `LiquidationPool` row codecs. Keep property
tooling out of application runtime dependencies and production domain modules.

- Names: empty/whitespace, trimming, lengths immediately below/at/above the
  declared limit, ASCII, combining marks, multi-code-point emoji, NUL, control
  and format characters. Separate bytes, code points and graphemes. Include
  malformed UTF-8 only at an entry point that can receive it; JSON transport
  rejection and domain rejection are different contracts.
- References: absent key versus explicit `nil`/`false`, numbers, list/map,
  empty/oversized string, unknown identity, foreign identity and owned identity.
  Verify creation/edit/delete semantics separately. Do not impose preset rules
  on commands with intentionally different identity contracts.
- Exercise domain dispatch and the `GameCommands.run/6` boundary. At that
boundary, keep cases within its field-count and encoded-size limits when
  testing downstream validation; separately test the payload envelope limits.
- Persist representative accepted Unicode boundaries and rejected unsafe inputs
  through the real server/database path. Assert unchanged entities, revision,
  receipt and ledger on rejection; a corrected request can still succeed.

For notices, extend
[localization tests](../test/tijara_tides/localization_test.exs) beyond catalogue
completeness. Obtain current notices from real domain transitions and render
them through `Notifications.render/2` in English and Arabic. Use independently
expected duration, money and other distinctive values so the old fallback cannot
pass as the current variant. Preserve explicit legacy-row fixtures too.

Begin with lease expiry, funding blocked/resumed/timeout and warehouse clearance.
Maintain a reviewed test inventory of supported codes and variants, mapping each
to its producer fixture and rendering assertion. New producer codes or required
arguments must update that inventory. Static extraction alone does not prove
runtime bindings survived the allowlist.

**Acceptance:** shared boundary cases detect the known name/identity errors;
domain-produced current lease expiry renders both rates and duration in both
locales, while the supported legacy row still renders its expected fallback.
Input and codec properties produce reproducible shrunk counterexamples under a
deliberate fault. A codec failure must identify the lost/changed semantic field.

## Round 2: Deterministic lifecycle interaction tests

Add short, named scenarios to the existing domain suites before extending random
generation. Drive ordinary transitions through `Commands.execute/4` and
`Game.advance/3`; retain focused lower-level tests for individual transitions.
Primary targets are `route_funding_test.exs`, `warehouse_liquidation_test.exs`
and the existing freshness, weather and handling suites.

| Scenario family | Variations to require |
|---|---|
| Funded repeating visit | Manual sail during an unfinished visit; pause then sail; resume; remove/change stop; failed departure; arrival and a second full visit |
| Accumulation handoff | Timeout then another claim in the same tick; cancellation/deletion; policy change; zero and partial accumulation; overdue bills; repeated unchanged retry |
| Award lease and receivership | Ordinary award resale versus liquidation-owned auction; bankruptcy before expiry, during grace and during liquidation; repeated full ticks through completion; a covered lease without a pool |
| Linked orders and purchases | Partial remote fill then departure, stop removal, Skip policy or lease expiry; completed goods retained while only unfilled demand and unused reservations release |
| Freshness and physical progress | Ordinary versus refrigerated aging around expiry; weather-delayed arrival crossing a shelf-life or visit deadline; handling already committed when expiry/liquidation starts |

Assert intermediate state after every action, not only the final result. In the
two-visit scenario, observe the old budget disappear, preserve the inbound
budget, then reserve the next visit's budget exactly once. In the receivership
scenario, confirm the pool is active and the ordinary auction actually invokes
the estate-cover path; a liquidation-owned auction can skip that path.

Use just-before, exactly-at and just-after deadlines with the correct clock.
Advance active-world and wall time independently where dormancy/recovery use
different clocks. Set up collisions deliberately, such as funding timeout and a
new eligible claimant in one full tick. Direct helper calls alone do not verify
phase ordering. Add coarse/fine tick comparisons only for behavior promised to
be tick-size independent, comparing semantic results rather than generated IDs,
journal grouping or incidental notice ordering.

**Acceptance:** each family has a reachable success path, a rejection/wait path,
and an explicit cleanup or terminal-state assertion. Full-loop tests fail if a
reservation leaks or a lease is revived, even when no exception is raised.

## Round 3: SQL transition and recovery contracts

Run a small, selected set of Round 2 traces through real PostgreSQL, committing
and reloading after each accepted transition. Compare authoritative entities
with the expected domain result, accounting for documented codec defaults and
transient journal/lot buffers. Check targeted SQL rows and independent expected
cash/reservation deltas, plus `FinancialLedger.audit/2`.

For departure handoffs, cover release-by-update and release-by-delete, followed
by an existing or newly inserted claimant. Assign IDs in both lexical orders
and vary entity insertion order. Keep zero-balance active windows in this matrix:
the partial unique index uses the deadline, not the accumulated amount. Also
test a deliberately invalid pair of active claims and require full rollback.

Inventory other immediate unique/check/foreign-key constraints touched by these
features. For each applicable ownership or allocation transfer, add a real SQL
test of the valid transition and a rollback test of the invalid result. Retain
the counting-double tests for batching cost; supplement them with ordering
assertions and representative chunk-boundary cases where batching can split
dependent writes. Avoid making every database scenario artificially enormous.

At selected checkpoints, replay a command receipt, restart/reload, retry an
unchanged tick and exercise existing ownership-fencing/failure hooks. Check
that effects occur once and no uncommitted projection is published. Distinguish
safe business rejection from persistence failure; storage failures must follow
the existing halt/recovery contract.

**Acceptance:** valid handoffs succeed regardless of relevant ID order; invalid
claims roll back; mid-visit and receivership traces survive commit/reload and
restart without changing deadlines or duplicating economic effects.

## Round 4: Stateful properties and generated workflows

Keep the current eight trading seeds. Add separate state-guided scenario families
for route funding/linked orders and award leases/receivership. Each family should
have a valid setup prefix, explicit operation preconditions and a small set of
legal actions, plus deliberate invalid actions with known rejection contracts.
Use StreamData to generate bounded scenario parameters and symbolic action
sequences. Start from known-valid fixture states rather than generating arbitrary
world maps. Extend the current local `:rand` workflows separately where useful.

The reference model tracks only the contract facts: selected stop and visit,
funds reserved/spent/released, accumulator identity and fixed deadline, and lease
or pool phase. It must not call production reconciliation predicates or copy the
whole simulation. Resolve symbolic references such as `ship_a` and `current_stop`
against each fresh fixture. Check command preconditions and postconditions,
then compare model facts and independent invariants after every action.

For the initial lifecycle properties, use a scenario skeleton whose essential
setup and transitions cannot disappear during shrinking. Shrink amounts, clock
offsets and optional intervening actions first. Free-form sequence shrinking
needs dependency checks so removing a creator does not leave invalid references.
Preserve the triggering path and the same semantic failure; reducing a budget
leak into an unrelated precondition failure is not a useful counterexample.

Check the Round 1–3 invariants after every action. Keep accepted-action progress
checks, but also require scenario-specific milestones: a handoff, a complete
return visit, partial fill and cancellation, or grace-to-liquidation-to-completion.
A high acceptance count from harmless ticks does not satisfy those milestones.

Every failure must print seed, initial configuration, clock advances, commands,
replies and the failing invariant. Provide deterministic trace replay and
minimize failures into short checked-in regression scenarios. Minimized traces
must still reach the relevant state; dropping an operation and making every
remaining command reject is not a valid reduction.
Start every generated case and shrink attempt from a fresh fixture. SQL cases
need isolated worlds and server cleanup for each replay, including failed
attempts; a preceding shrink attempt must not affect the next one.

Start with bounded fixed seeds in the ordinary suite and a few short SQL-backed
traces in the database suite. Offer a separate opt-in larger seed sweep; measure
runtime before widening the mandatory cohort. Reuse trace descriptions across
pure and SQL runners, keeping their persistence/publication assertions separate.
Initial implementation caps: four seeds per new domain family, up to 60 actions
each; two SQL traces per family, up to 25 actions each. These are work bounds,
not coverage claims: each trace must still reach its declared milestones.
For StreamData, start with 50 cases per pure input/codec property and 20 cases
per lifecycle property, at most 30 actions per generated sequence and 100
shrinking steps. Use only five short cases per initial SQL property, bounded to
15 actions and 20 shrinking steps; measure before widening. These count limits
include neither fixtures nor the existing fixed traces. Retain the existing
test timeout and cap fixture sizes too: shrinking can multiply database work.
Use the same mandatory budgets locally and in CI. Retain fixed seeds for the
known adversarial families, plus an ExUnit-seeded property run whose seed is
reported on failure. Archive the minimized trace and revision; a seed alone may
stop reproducing after a generator or dependency changes.

**Acceptance:** fixed runs reach every declared milestone and can be replayed
exactly; rejected operations preserve protected state. Failure diagnostics are
sufficient to reproduce a sequence without rerunning a seed search.
Shrinking retains the relevant lifecycle path and semantic failure. Every replay
starts from clean state, and the required input/scenario categories have explicit
coverage evidence alongside randomized exploration.

## Round 5: Mutation testing and review enforcement

Extend the bounded mutation/fault audit with one semantic fault for each recent
escape: grapheme counting instead of code-point counting; omitted rate binding
or wrong-key renderer clause; claims written before releases; omitted departure
budget release or visit-identity check; removed active-pool guard; unsafe name
or arbitrary preset identity admitted. Keep each fault isolated so the relevant
assertion fails after successful fixture setup, rather than detecting an
unrelated compilation or startup failure.

Use isolated disposable checkouts, an unmutated baseline, exact patches and
explicit test selections including indirect callers. Retain failure evidence
and report survivors, invalid mutations, timeouts and selection misses separately.
Keep broad generated mutation testing opt-in as the existing pilot recommends.

Add a generated cohort around validation comparisons, Boolean guards, budget
arithmetic, deadline comparisons and lifecycle clauses. Start with at most 20
mutants per selected source and 60 per audit, one worker and a 30-second per-mutant
timeout, then measure before expanding. Curated patches remain a separate cohort.
Include relevant property tests in the explicit test selection, with stable
seeds and bounded generation/shrinking so results can be repeated.

For each surviving generated mutant, replay the same patch with the full
applicable suite, including disposable PostgreSQL. Classify a selection miss
separately from an assertion/generator gap. For a real gap, add a counterexample
and improve the general property or generator, then rerun that exact mutant.
Document genuinely equivalent or diagnostic-only mutants with the reason; do
not label a survivor equivalent merely because current tests do not fail.
Do not count skipped database tests, timeouts or compilation failures as kills.

Produce a detection matrix linking each curated fault and selected generated
mutant to the detecting named test/property and its failure evidence. Where
practical, compare named tests alone with named tests plus properties using the
same mutant cohort and seeds. This measures the properties' additional detection
without rewarding an increased test count. Known defects should have mandatory
ordinary regressions; the slower mutation audit checks their sensitivity.

Expand the testing policy's scenario matrix with named tests for these contract
families. For future stateful changes, require a review entry identifying:

1. Changed decisions and input boundaries, with named tests or justified
   infeasible cases.
2. Resources acquired, consumed, transferred and released, including every exit
   path and retained inbound/committed obligations.
3. Interacting lifecycle phases, timers and clocks, with a reachable sequence.
4. SQL constraints and write order, replay/restart and publication behavior.
5. The independent oracle and an applicable semantic fault it detects.

This makes the existing review policy concrete; it does not claim automatic
branch coverage. Implementing validated branch/condition instrumentation remains
a separate follow-up under the acceptance criteria in the testing policy.

**Acceptance:** every curated fault is detected by its intended assertion; the
restored baseline passes. The scenario matrix links concrete named tests, and
the ordinary fixed-seed and PostgreSQL cases run under existing local/CI checks.
The mutation report distinguishes missing generation from weak assertions and
selection failures, with all survivors triaged and exact replay evidence retained.

## Execution and completion

Implement in the order above, committing each completed round after its focused
tests and the applicable normal checks pass. Use `mix precommit` and
`python3 scripts/test-game-db.py --cover` for final verification of each round
that changes executable tests. Preserve the existing CI runtime matrix and
90% line gate. Extended seed sweeps and mutation audits remain separate opt-in
commands, with bounded work and diagnostic artifacts.

Measure baseline and added runtime on the same machine before setting a larger
mandatory seed budget. No sleeps, external services or production database are
needed. Put reusable fixtures/assertions in `test/support`; keep expected rules
small and explicit instead of rebuilding the game engine in tests. Split new
persistence scenarios into focused modules using the existing database setup
conventions rather than adding indefinitely to the large integration file.

Completion means the six recent escape mechanisms have direct detection
evidence, their adjacent lifecycle combinations have named coverage, generated
families demonstrably reach their required states, and SQL/recovery checks verify
the durable result. Test count and line coverage alone are not completion criteria.
