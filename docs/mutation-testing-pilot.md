# Mutation-testing pilot — 2026-09-18

The initial bounded pilot found one genuine gap in the full suite's assertions and a
Muex test-selection limitation. The [five-area expansion](#expansion-to-all-five-areas)
added five focused tests and confirmed further selection limitations. Tests now cover overdue interest in exact payoff
eligibility and give faster, bounded feedback on retry regressions. Production
code, dependency declarations, and CI configuration are unchanged.

## Initial pilot results

Muex 0.11.2 ran in an isolated checkout on Elixir 1.20.2 / OTP 29.0.4. The earlier
compatibility trial also exercised Elixir 1.19.3 / OTP 28.4.2; this pilot's complete
mutation cohort was run only on 1.20.2 / OTP 29.0.4. Starting source commit:
`b9735f888b12d9b2697cdf9e097141a13308188c`.

| Distinct mutations | Initially | After test changes and corrected selection |
|---|---:|---:|
| Detected by failing tests | 41 | 47 |
| Survived selected tests | 4 | 0 |
| Timed out | 2 | 0 |
| Invalid / uncovered | 0 | 0 |
| Total | 47 | 47 |

Three runs executed 49 mutations with two duplicates: 20 finance mutations,
20 retry/commit mutations, and 9 Boolean/arithmetic mutations extending through
commit and replay acceptance. The initial file cap stopped before the acceptance
branches, so the third run ensured those branches were actually included.
The table deduplicates identical source-location/operator/patch combinations.
Initial and final unique manifests match exactly; every final detection names
a failing test. This is 100% detection of this sample, not of the whole system,
and it is not a branch/condition coverage percentage.

The initial three mutation runs took 181.08 seconds combined. The final
three runs took 119.27 seconds, including coverage-guided test selection
but excluding the separate baseline/post checks and full-suite verification.
These are local warm-build measurements, not a CI performance guarantee.

## What improved

### Overdue interest was missing from payoff assertions

Changing `loan.remaining + loan.interest_due` to
`loan.remaining - loan.interest_due` survived all **651 original tests**, including
real PostgreSQL tests. Existing exact-payoff assertions used zero overdue interest.
This was a test gap; the unmutated production formula was already correct.

`test/tijara_tides/domain/loan_actions_test.exs` now checks a loan with both overdue
and newly accrued interest. Available cash immediately below, equal to, and above
the 10,400-cent payoff must produce the correct eligibility. Reserved funds stay
unavailable, overdue principal is not counted twice, and recasting remains disabled.

### Retry tests now fail promptly on unbounded work

Two mutations prevented retry progress: decrementing by zero and incrementing the
retry budget. They initially timed out before the assertions after the retry loop
could execute. Both persistent-conflict scenarios now assert the allowed number
of attempts/reloads inside the fake-store interaction. Excess work fails as a
normal assertion rather than waiting for an external timeout.

A focused test also checks that a no-conflict operation preserves both a successful
`CommandResult` and a rejected result without a reload. The broader original
suite already rejected an incorrectly set refreshed flag in four tests; this
addition improves the focused retry suite rather than claiming another full-suite
gap.

## Muex selection finding

Passing several files to `--test-paths` does not force Muex to run all of them.
Its default dependency analysis selected only `replan_test.exs` for mutations in
`CommitExecutor`, dropping the supplied command tests that call it indirectly.
This produced three apparent gaps: the initial refreshed flag and the committed
flags on success and replay.

Ordinary ExUnit caught those mutations using existing tests. The refreshed flag
failed four tests in a full-suite replay; the success/replay flags failed the
existing command/lifecycle tests. These are selection gaps, not three missing
application safeguards.

The final run used `--coverage-guided`. Reports confirm that the success/replay
mutations selected `game_commands_test.exs`, and all sampled mutations were caught.
The pilot validates this selection for these targets, not arbitrary future code.
Coverage guidance uses executable-line coverage to choose tests; it does not
instrument Elixir branch or condition coverage.

## Verification

- Ordinary unmutated baseline before every Muex run, followed by a post-run check.
- Full original suite: 651 passed. Finance mutant: 651 passed. Refreshed-flag
  mutant: four failures. Restored original suite: 651 passed.
- Updated `mix precommit`: passed, including formatting, compilation, translation
  checks, and tests (592 passed; 61 database tests excluded by this command).
- Updated `python3 scripts/test-game-db.py --cover`: **653 passed**, **93.48% line
  coverage**, above the existing 90% minimum, using disposable PostgreSQL.
- All mutation source changes were confined to disposable copies and restored.
  The only executable repository changes are tests.

## Recommendation and operating rules

Keep mutation testing as a bounded opt-in audit for now. Do not introduce a
project-wide mandatory score from a deliberately small sample that includes easy
function-name mutations as well as meaningful domain mutations. The pilot shows
useful assertion feedback, but also shows why reports need inspection.

Before a future CI gate:

1. Pin Muex and retain source hashes, exact patches, test-file selections, runtime,
   counts, and actual failure evidence.
2. Require the selected tests to pass unmutated in the same environment first.
   Muex's automatic baseline is limited to umbrella projects; this project is not
   an umbrella. A pre-existing failure can otherwise produce a false-green score.
3. Use validated coverage-guided selection for indirect callers. Inspect missing
   coverage and unexpected test-file selections instead of accepting a score alone.
4. Keep one worker, deterministic ExUnit seed, explicit source scope, and bounded
   mutation/time limits until broader concurrency and repeatability checks justify
   expansion. Report invalid, timed-out, and uncovered results separately.
5. Establish a representative repeatable cohort before making it merge-blocking.
   Mutation scores complement the separate branch/condition testing requirement.

## Reproduction

Muex was a test-only dependency in the isolated pilot copy, using the unmodified
published 0.11.2 archive (SHA-256
`a0898a28179e279e603a1e1e8ab25dc9e9a40791cfd0409ea093d2d6c7800cb7`). It is not installed
in this repository. An isolated reproduction must first make that exact version
available to Mix and configure its test helper with ExUnit seed 12345.

For each source below, run the listed tests unmutated, then Muex with:
`--no-filter --no-optimize --no-tce --concurrency 1 --timeout 30000
--coverage-guided --fail-at 0 --format json --output <report.json>`.
`--fail-at 0` collects diagnostic results; it is not a quality gate.

| Source under `lib/tijara_tides/` | Mutators | Cap |
|---|---|---:|
| `domain/company_finance/loan_actions.ex` | comparison,boolean,arithmetic | 20 |
| `use_cases/commit_executor.ex` | boolean,comparison,literal | 20 |
| `use_cases/commit_executor.ex` | boolean,arithmetic | 10 (9 generated) |

Finance test files under `test/tijara_tides/domain/`: `loan_actions_test.exs`,
`finance_test.exs`, `company_finance_aggregate_test.exs`.
Commit/replay files under `test/tijara_tides/use_cases/`: `replan_test.exs`,
`game_commands_test.exs`, `lifecycle_commands_test.exs`, `commit_preparation_test.exs`.
Pass these through `--test-paths`, and each source through `--files`. Save JSON
reports and verify each mutant's recorded test files and outcome.

Local raw evidence and replay scripts are in `cover/mutation-pilot/` (ignored,
not part of a fresh clone). This includes `SUMMARY.json`, before/after reports,
full-suite logs, the reproduction harness, and saved-patch triage scripts. The
harness retains paths to its isolated pilot copy; the commands/scopes above describe
how to reproduce in another checkout.

## Expansion to all five areas

The follow-up retains the initial 47-mutant finance/retry/commit cohort and adds
60 generated mutants plus seven deliberately selected fault injections. All expansion
runs use the same pinned Muex package and Elixir 1.20.2 / OTP 29.0.4 runtime. This
is a bounded audit across all five areas, not exhaustive mutation of every file.

| Area | Evidence exercised |
|---|---|
| Finance | Original 20 loan eligibility mutations; multiple journal entries when establishing a new company's accounting baseline |
| Trading instructions | All 34 Boolean, comparison and arithmetic mutations generated for `Ship.VisitOrder`; fill admission, progress, budget, maximum quantity and archive defaults |
| Commit/replay | Original `CommitExecutor` sample, all nine generated `CommitPreparation` mutants, plus replay returning the speculative result instead of the stored receipt |
| Conflict recovery | Original bounded retry sample, plus retrying the stale snapshot instead of the reloaded state and bypassing the SQL ownership fence |
| Persistence failures | All 17 Boolean/literal `OperationBoundary` mutants, plus removing the commit transaction, bypassing it only for a failed receipt, accepting a failed commit and broadcasting after failure |

The new generated cohorts use a cap of 40 each; none reaches that cap. Baselines
and post-run tests include disposable PostgreSQL where applicable. Each curated
fault is a saved source patch tested independently with the full suite, with
source restored after every attempt. Curated faults are reported separately from
Muex-generated results.

### Assertion improvements and triage

Before adding the five expansion tests, the full suite passed 653 tests. Five
behavior-changing generated mutants also passed that entire suite:

- Both default archive flags could become true, hiding newly created or legacy
  instruction history. The test now checks fresh, legacy and explicit archive states.
- The independent status/positive-quantity rejection could become an `and`, allowing
  an inactive order with remaining capacity or a zero fill. Both rejection conditions
  are now tested independently.
- Maximum fills could terminate at a full 10,000-unit batch. The test compares 9,999
  with exactly 10,000 while more quantity remains.
- A new company's second accounting adjustment could be subtracted instead of added.
  The test checks two distinct postings and the exact resulting capital balance.

Two apparent gaps were already caught by the full suite. Reversing the maximum
fill comparison failed existing `ship_routes_test.exs` scenarios, a file omitted
from the initial narrow instruction scope. The final scope includes it. Changing
`old == new` to `old != new` in market version preparation failed existing database
tests even though Muex labelled it `no_coverage`. Coverage-guided selection is
therefore still a heuristic: an uncovered report is not proof of absent assertions.
A focused test now checks unchanged, updated, inserted and deleted market versions.
Muex still labels this mutant `no_coverage` after that addition; the manual replay
proves test detection, but it remains an unresolved automatic selection limitation.

Two surviving instruction mutations only change arithmetic inside an exception's
message; rejection behavior remains intact. They are diagnostic-only survivors,
not proven equivalent mutants and not counted as detected. Four generated mutations
produce invalid capture syntax (`&0` or a skipped capture argument). Invalid mutants
are tool-generation failures, not evidence of resilience.

### Expansion reproduction

Use the same Muex flags and separate baseline/post checks described above, with
`--max-mutations 40`, one worker, `ERL_FLAGS="+S 4"`, and ExUnit seed 12345.

| Source | Mutators | Test files under `test/tijara_tides/` |
|---|---|---|
| `domain/ship/visit_order.ex` | comparison,boolean,arithmetic | `domain/ship_aggregate_test.exs`, `domain/ship_instructions_test.exs`, `domain/ship_routes_test.exs` |
| `use_cases/commit_preparation.ex` | comparison,boolean,arithmetic | `use_cases/commit_preparation_test.exs`, `infrastructure/game_persistence_test.exs` |
| `infrastructure/operation_boundary.ex` | boolean,literal | `infrastructure/operation_boundary_test.exs`, `infrastructure/game_server_failures_test.exs`, `infrastructure/game_persistence_test.exs` |

The source prefix is `lib/tijara_tides/`. Database-enabled scopes must inherit only
the disposable cluster's `TIJARA_TEST_DB_PORT`, with production database environment
variables removed. Raw expansion reports, full-suite survivor replays, exact curated
patches, runtime/source hashes and scripts live in `cover/mutation-expansion/`
(ignored local evidence). Scripts retain the isolated checkout path.

The broad transaction-removal injection fails during world setup as well as tests;
that proves detection but does not isolate rollback assertions. The additional
receipt-failure injection preserves normal transactions and bypasses one only when
the receipt fingerprint is nil. This deliberately narrow fault allows the normal
world setup to finish before exercising failed-write atomicity.
It fails the existing rollback assertion because SQL returns `[["rollback-probe"]]`
instead of an empty result. All seven curated faults are detected. The six broad
faults were tested against the pre-expansion 653-test suite; the narrow atomicity
fault was tested against the updated 658-test suite. Both restored suites pass.

### Expanded generated-cohort results

| New generated mutations | Before expansion tests | Final rerun |
|---|---:|---:|
| Detected by Muex-selected tests | 47 | 53 |
| Survived selected tests | 8 | 2 |
| Invalid capture syntax | 4 | 4 |
| Reported uncovered | 1 | 1 |
| Timed out | 0 | 0 |
| Total | 60 | 60 |

The two final survivors affect exception-message arithmetic only. The one reported
uncovered mutant fails ordinary full-suite replay. These results deliberately retain
Muex's raw classifications instead of turning manual triage into an inflated score.
Together with the previous 47-mutant final pilot, the generated audit comprises
107 distinct mutants: 100 detected automatically, two diagnostic-only survivors,
four invalid, and one detected manually but skipped by Muex coverage selection.


The initial and final expansion manifests match exactly by source location,
mutator and replacement patch. Final generated runs took 195.91 seconds combined,
including coverage guidance but excluding baseline/post checks and manual replays.
The initial generated runs took 222.40 seconds. These are warm local measurements.

Final repository verification: `mix precommit` passed (597 tests; 61 database tests
excluded), and `python3 scripts/test-game-db.py --cover` passed all **658 tests**
with **93.48% Elixir line coverage**. The expansion ran on Elixir 1.20.2 / OTP 29.0.4;
only the earlier compatibility trial covered both runtime pairs. Production source,
dependencies and CI remain unchanged. Keep the audit opt-in: the uncovered-condition
selection miss must be addressed before treating an automatic score as a gate.
The separate branch/condition review requirement still applies; these mutation
results do not supply measured branch or condition coverage.
