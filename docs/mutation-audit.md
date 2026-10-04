# Test expansion mutation audit

This Round 5 audit checks the sensitivity of selected assertions. It is not a
whole-project mutation score or proof that the game has no latent defects. The
[discovery matrix](test-discovery-matrix.md) records the wider scope, including
areas deliberately left outside this generated sample.

The source baseline is `7e7e5f2` plus the Round 5 test/tooling changes committed
with this report. Local execution uses Elixir 1.20.4, OTP 29.1 and seed 12345.
Both configured CI runtime combinations remain CI verification requirements;
these local receipts do not establish their results.

## Method and work limits

`scripts/mutation-audit.py` copies the checkout into a temporary directory and
uses its own disposable PostgreSQL cluster. Mutations never touch the working
source, local playtest storage or deployed storage. Each invocation has one
worker. Curated invocations accept at most twelve exact patches; the generated
audit accepts twenty candidates per source and sixty total. Each mutant first
compiles under the 120-second diagnostic limit, so recompiling dependents never
consumes its 30-second test limit. Unmutated/restored baselines and
full-applicable survivor triage share the 120-second diagnostic limit. Full SQL
triage took about 40 seconds locally, so it cannot honestly share the shorter
mutant budget.

Muex 0.11.2 is checksum pinned in an isolated tool project; it does not enter the
application dependency list or lock. The exporter uses comparison, Boolean and
arithmetic operators, taking the first twenty locatable candidates in each
selected source. This deterministic cap samples those sources' early clauses;
it does not cover every decision in those files. The explicit test selection
includes indirect callers and the bounded command-fuzzer properties. It bypasses
Muex's dependency-selection heuristic.

Generated AST rendering has its own canonical, unmutated baseline before each
mutation. Each worker then runs the exact mutant and restores the original
source with another passing baseline. Exact sources, patches, source/patch
hashes, origin commits, runtime, commands and failing test names are retained
under `cover/test-expansion/round5/`. New invocations also record the test-source
hashes and working-tree status; an uncommitted test is not implied by `HEAD`.
The compact checked-in results preserve the finding-to-test mapping; detailed
logs remain local artifacts and are included in CI's `cover/` upload when an
audit runs there.

An exit code alone never counts as detection. Compile errors, startup/setup
failures, timeouts and harness failures have distinct classifications. Curated
faults also require their named witness. The initial witness expressions were
too narrow for several deliberate `flunk` messages and the SQL unique-index
failure. Those logs were reviewed, the initial labels retained, and the affected
cases rerun with the correct witness; no assertion was changed to accommodate
the classifier. Isolated recompilation can print timestamp-reset warnings, and
deliberate source faults can cause compiler warnings. Neither is a detection.
The restored application gates must still compile without warnings.

## Generated discovery in earlier code

The initial cohort has exactly sixty candidates across three areas. Git blame
and ancestry establish that 57 mutated lines predate the review base `5ad0399`;
the other three are recorded individually. This exceeds the planned earlier-code
allocation without drawing the sample solely from the reviewed feature diff.

| Area / source | Initially detected | Selection misses | Survived applicable suite |
|---|---:|---:|---:|
| Finance / `company_finance/loan_actions.ex` | 20 | 0 | 0 |
| Markets / `port_cargo_market.ex` | 10 | 2 | 8 |
| Accounts / `account.ex` | 15 | 0 | 5 |

Every initial survivor received the **same** mutant in its full applicable scope,
including persistence, SQL fuzzer and SQL transition tests. Market candidates
32 and 37 were detected there, exposing a selection miss rather than an assertion
gap. The other thirteen survived that scope; none was dismissed as equivalent.

| Initial gap | Exact candidates | Independent contract added |
|---|---|---|
| Merchant storage active by default | 21 | New and decoded merchants start unbacked and cannot expose manual trading |
| Reversed/removed scarcity adjustments | 24, 27, 30, 33 | Hand-authored ask/bid multipliers at stock/demand 0, 250 and 500, varied reference prices and merchant status |
| Permissive manual trading guard | 35 | Manual permission and merchant backing vary independently |
| Ignored buyer funding / zero-price division | 38, 39 | Independently funded unit limits and explicit free-goods demand |
| Quota/suspension guard weakened | 43, 44, 47, 54 | Quota, suspension and outstanding capacity vary independently; zero-quota issue returns its business rejection before consumption |
| Fractional/nonpositive invitation earnings | 59 | Positive whole counts only, with fixed zero, negative and fractional examples |

`MarketQuotePropertiesTest` adds two 50-case properties and three named examples.
`AccountQuotaPropertiesTest` adds two 50-case properties and three named examples,
including the checked-in zero-quota counterexample. Both use 100 shrink steps.
The counterexamples describe incorrect mutations of otherwise correct source;
they are test-discovery evidence, not claims of production defects. All thirteen
survivors and both selection misses are caught on exact replay with the new
contracts, with passing unmutated and restored selections.

The fixed comparison keeps the same source, selection and seed, excluding only
tests tagged `:property` in the named-only run:

| Candidate | Named tests alone | Named tests plus properties |
|---|---|---|
| 24, reverse asking-price scarcity | Detected by the fixed endpoint counterexample | Detected |
| 30, reverse bidding-price scarcity | Survived | Detected by the varied price-point property |

This is a two-candidate sensitivity comparison, not a percentage for all tests.
Both comparison baselines/restorations pass. The intentionally surviving
named-only run exits nonzero and remains recorded as such.

## Curated mechanisms and newly exposed gaps

The catalogue has 32 single-file faults in three bounded invocations. It covers
all eighteen review findings, both design decisions, the subsequent web-field
escape, and selected established finance, reporting, identity and boundary rules.
The checked-in catalogue specifies each exact patch, selection and witness.
The discovery matrix maps review items to these faults and the actual detecting
test; the compact results retain all failed test names, rather than a score.

Four faults initially survived their selections, prompting stronger contracts:

| Fault | Missing observation | New independent evidence |
|---|---|---|
| `future-weather` | Short voyages ended before another undisclosed storm | A long voyage during a disclosed storm may contain only its known hold, with exact remaining delay; offsets/durations also vary in a property |
| `filtered-check-unfiltered-take` | Eligibility was checked without observing forced-sale cargo identities | A prepared live pool fills a buyer from the fresh lot while the older lot stays in the source warehouse |
| `merchant-reservations` | The offered quantity did not exceed remaining unreserved stock | Supply at free capacity preserves reserved physical units; one unit above capacity raises, over varied stock/reservations |
| `grace-rent` | Tick-partition agreement shared the same wrong rate | Independently calculated cents and remainder distinguish grace time from later surcharged time, including a fixed late tick |

Each new property has 50 cases and 100 shrink steps, paired with a fixed example.
The forced-sale case verifies both source and destination through the existing
owning roots; the other full-tick liquidation and SQL recovery tests remain in
the ordinary suite. These tests supplement existing evidence rather than treating
every helper test as a complete lifecycle test.

All 32 curated faults have detecting named tests/properties and passing restored
baselines. The previously surviving four have exact rerun receipts with their
stronger observations. Instrumentation-sensitive cost and architecture tests
also pass alone in a fresh VM (ten tests, about 0.1 seconds); the compiled back-edge
and repeated-work faults fail their guards. The ordinary full suite verifies
those modules again without relying on prior test loading.

A 33rd curated fault, `stale-route-cancellation`, was added with the rendered
command control sweep. Its catalogue entry opts the CI-only sweep in and focuses
it on the waiting-route scenario's cancellation button through per-fault
environment variables; corrupting that button's ID is detected.

## Normal verification and measured cost

`mix precommit` passes 874 tests/properties in 9.6 seconds. The disposable
PostgreSQL coverage run passes 991 (29 properties, 962 named tests) in
47.4 seconds with 94.01% line coverage. Both real Chromium workflows pass in
4.4 seconds. Precommit and SQL compilation each have zero compiler warnings.
Generated-document checks, the three audit-classification tests, 23 validation
scope tests, shellcheck and actionlint also pass. Raw receipts are under the
Round 5 artifact directory.

The initial generated mutant workers total 257.7 seconds, with a maximum of
5.2 seconds each. Separate baseline/restoration/SQL-triage checks total
1196.3 seconds; the longest triage is 42.18 seconds. Tool setup and exact
counterexample replays are additional work. This explains why the audit remains
opt-in while the new contracts enter the ordinary suite. Mandatory fuzzer
cohorts and the line-coverage threshold were not increased.

## Suggested-order outcome audit, 2026-10-04

The next-port purchase default could exceed the quantity executable while
preserving onward funds. Submission, partial-fill and departure guards all
passed independently because no contract connected that default to completion.
The fix shares manual purchase limits with next-port suggestions and projects
known inbound costs. Additional contracts cover funded sale demand, expired
cargo, visit funding, freshness and the owned-stock source chosen by execution.

`instruction_offers_test.exs` contains eleven named witnesses and four shrinking
properties. Three properties run fifty cases each; the full travel property
runs thirty. The SQL journey submits rendered defaults unchanged, fills the
entire target and sails after handling, then verifies reload and restart. The
control sweep also retains rendered purchase quantities and adds a buy-visit
scenario. These tests run through real commands and transitions; an accepted
instruction alone is not their outcome oracle.

Nine curated faults at catalogue indices 36 through 44 cover voyage funding,
occupied hold space, qualifying freshness, funded sale demand, owned-source
selection, inbound costs, warehouse stock claims, sale expiry filtering and blank
shelf-life form fields. All nine fail the new assertions, with passing unmutated
and restored baselines. The inbound-cost fault also fails the SQL rendered-default
journey. Compact source/patch hashes, test hashes and detecting test names are
recorded in `test/fixtures/mutation_faults/suggested-outcomes-results.json`.
Detailed receipts remain in `cover/mutation-audit/suggested-outcomes/`.

```sh
python3 scripts/mutation-audit.py curated --start 36 --count 9 --out cover/mutation-audit/suggested-outcomes
```

This cohort establishes sensitivity for those nine faults. It does not extend
the shared command fuzzer's inventory to single-visit instruction sequences or
turn a future quote into a resource reservation. Explicit price overrides and
subsequent market changes can still require waiting.

## Remaining discovery work

The audit is deliberately bounded. Existing tests cover manufacturing recipes,
participation credits, berth queues, reporting and recovery; only selected faults
in those areas were audited here. Generated manufacturing/participation and
additional ownership/queue clauses remain candidates for the next measured
cohort, as do generated deadline/lifecycle clauses beyond this sample. Named
boundary faults already cover the selected deadlines. Linked-order partial
fills and handoffs retain named/SQL regressions but
are not generated by the initial route skeleton. Other command/form exclusions
remain visible in the checked inventory.

Validated branch/condition instrumentation remains the separate follow-up in
the testing policy. Corpus interest and successful seeds are not branch coverage.
The 90% line gate stays unchanged. New counterexamples run in ordinary checks;
extended fuzz sweeps and source-mutation audits remain opt-in.
