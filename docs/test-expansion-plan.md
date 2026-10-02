# Proposed test expansion

Status: Round 0 is documented. Round 1a is implemented with seven bounded codec
properties and independent structural/legacy tables. Round 1b adds payload,
notice and SQL/browser form contracts. Round 2 adds audited full-tick lifecycle
and adjacent-boundary scenarios. Round 3 adds SQL handoff permutations, rollback
and chunk-boundary contracts, plus isolated historical migrations. Rounds 4–5
remain planned.
Each executable round is committed after its focused and normal checks. Runtime
matrix verification remains a CI gate; local evidence uses Elixir 1.20.4/OTP 29.1.

## Goal and current evidence

Find latent defects throughout the existing game, including code written before
the gameplay automation branch. The review's 18 findings and two resolved design
questions supply initial counterexamples and fault patterns. They do not bound
the expansion's scope or define its completion criteria.

Organize coverage around business invariants, resource lifetimes, information
boundaries and subsystem interactions. Retain direct regressions for known bugs
while independently exploring established behavior that has no reported defect.
Build a stateful command fuzzer within the shared property/trace runner. Its
payload mode starts in Round 1b; its sequence mode and SQL replay land in Round 4.

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

## Discovery scope and selection

Use the following inventory to select work across earlier and recent code.
The test suites listed are starting points, not claims that these contracts are
fully covered. The Round 0 [discovery matrix](test-discovery-matrix.md) records
initial named evidence, proposed boundaries/interactions, independent oracles,
candidate semantic faults and target rounds. Before implementing each selected
scenario, audit the existing assertions and record its precise remaining gap.
It also maps every review finding and design decision to its regressions and
proposed generalization. Keep this inventory current as rounds land; the completed
fault-detection evidence is added in Round 5.
Include a command-generator inventory and its supported entry points, expected
errors, milestones and exclusions. Discovery must expose ungenerated commands
instead of treating a successful fuzz run as whole-command coverage.
Also inventory command-producing web forms and their variants: a command covered
below `GameLive` does not prove that its browser submission is normalized safely.

| Area and existing test foundations | Discovery targets |
|---|---|
| Finance and guarantees: `finance_test.exs`, `guarantees_test.exs`, `loan_actions_test.exs` | Protected versus available funds; interest and repayment boundaries; sponsor/beneficiary settlement; refunds and bankruptcy without duplicated charges |
| Trading and auctions: `exchange_test.exs`, `auctions_test.exs`, `graded_books_test.exs` | Partial fill/amend/cancel sequences; exact eligible lot selection; competing reservations; priority; two-company transfers and receiving capacity |
| Fleet and berths: `port_berths_test.exs`, `rerouting_test.exs`, `ship_maintenance_test.exs` | Queue retries and invalid heads; committed handling; reroute/disposal; fuel and cost already spent; completion or release on every exit |
| Port economy: `manufacturing_test.exs`, `participation_test.exs`, `regional_pricing_test.exs` | Recipe inputs/output/costs; finite stock and buyer budgets; participation changes; replenishment after reload without reseeding |
| Accounts and identity: `email_identity_test.exs`, `invitation_accrual_test.exs`, `identity_history_test.exs` | Ownership and privacy; expiry using the correct clock; retry and quota recovery; compaction retaining pending work |
| Reporting and queries: `reporting_test.exs`, application query and projection tests | Independent event-to-total calculations; period boundaries; borrowing versus profit; owner/public views; committed projection consistency |
| Storage, automation and weather: existing warehouse, route, freshness and weather suites | Phase collisions; receiver-based eligibility; irreversible deadlines; frozen voyage facts; disclosed weather only; late settlement |
| Persistence and recovery: database, commit/replay and failure suites | Valid historical rows and migration defaults; atomic rollback; receipt replay; ownership fencing; reconstruction of derived state |
| Architecture and work bounds: `test/docs` boundary suites and operation-count tests | Relevant compiled dependency paths; query purity; repeated collection traversal; commit/broadcast amplification; test-order independence |

Prioritize by failure impact, reachable complexity and weak assertion coverage,
regardless of code age or whether a file was changed by the reviewed branch.
Trace resource acquisitions and exits, command reconciliation and the full
`Simulation.advance` phase list. Inventory tick-reachable raises and SQL
constraints as candidate outage paths; test legal transitions cannot reach them
and invalid input follows its declared rejection or halt contract.

Use small, valid established-world fixtures as well as empty/new worlds: existing
cash, partially paid loans, queued trades, holdings across ships and warehouses,
pending identity work, accumulated reports and historical supported row shapes.
Create them through legal transitions or documented historical fixtures; arbitrary
malformed state belongs in explicit corruption/recovery tests. Change one relevant
fact at a time, then deliberately collide two lifecycles. Example combinations
include repayment with reserved bid funds, sponsor settlement after beneficiary
bankruptcy, queued handling followed by cancellation, and replenishment after
restart with existing inventory. These are discovery scenarios, not new findings.

Cover the applicable boundary and interaction for every inventory area with named
tests in Rounds 1–3, reusing existing coverage when it supplies the stated oracle.
Round 4 initially adds four generated domain families: route funding/linked
orders, award leases/receivership, finance/guarantees, and berth/trade/rerouting.
Choose one short SQL replay per family first, then the second within the declared
budget. Additional generated families need measured runtime and an explicit
inventory update; the broader scope must not silently multiply CI work.

## How property and mutation testing fit

Use both throughout the rounds. Property tests express rules over generated
inputs and sequences; shrinking helps produce a smaller failing example.
Mutation tests deliberately break a rule to check whether the assertions detect
it. Named regressions preserve previously discovered counterexamples.

Add **StreamData with ExUnitProperties** as a test-only dependency in Round 1a,
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
| Browser-form admission | Valid form variants, untouched-input metadata, optional/hidden/disabled fields and equivalent numeric formatting | Intended persisted effect; equivalent submissions replay the same receipt; no UI-only fields reach the command envelope |
| Row codecs | Valid typed budgets, requests and pools, including optional fields and boundary values | Decode/encode preserves semantic fields; hand-authored row expectations prevent two matching codec mistakes from passing |
| Budget conservation | Valid reserve/consume/resize/release sequences | Initial allocation plus net adjustments equals purchases plus released and remaining funds; visit identity stays correct |
| Funding lifecycle | Waiting ages, available cash, policies, zero/partial windows and deadline offsets | One active accumulator; fixed deadline; no double reservation; oldest eligible allocation under fixture rules |
| Liquidation lifecycle | Occupancy, charges, proceeds, deadline offsets and estate-cover attempts | Occupancy cannot grow during liquidation; cover does not revive the lease; proceeds/charges reconcile once |
| Persistence transitions | Equivalent handoffs with different IDs and insertion orders | Every valid transition commits; invalid claims roll back; reload preserves authoritative state |
| Established finance and queues | Debt/payment/reservation boundaries; two-company guarantee events; queue admission, retry, cancellation and rerouting | Independent amounts and fixed deadlines; preserved committed work; eligible queue progress without duplicate settlement |
| Economy, identity and reporting | Valid recipes and inventories; participation offsets; token/quota clocks; hand-authored accounting events and period boundaries | Explicit recipe transformations and sinks; no reload reseeding; owner-only data; recoverable pending work; independently calculated totals |
| Command fuzzing | Mutated payloads and model-guided commands across accounts, ticks and lifecycle families | Declared admission/error contract; invariant checks after each step; unexpected exceptions or internal error results are findings |

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

For earlier code, define equally explicit oracles. Manufacturing transforms inputs
into outputs and incurs costs; replenishment, spoilage and bankruptcy have declared
sources or sinks, so blanket conservation of every quantity is incorrect. Model
those deltas from fixture facts. Check privacy against owner/foreign/public views
and reporting against hand-authored events. Compare tick partitions, cached versus
uncached results, reloads and reordered independent actions only where the design
promises equivalent behavior; agreement between two production paths can share a
bug and needs independent expected facts too.

## Round 0: Review checklist

Apply the five-question checklist in the
[testing policy](testing-and-coverage.md#stateful-change-review-checklist)
immediately to stateful changes, including feature work landing alongside the
test expansion. This documentation round needs no new dependency or test runner.

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

**Acceptance:** the checklist is in the testing policy and applies immediately.
The discovery matrix records initial named evidence and proposed exploration
across the inventory, including earlier code and all review findings/design
decisions. Audit assertions and select precise gaps before each executable round.
The later detection-matrix links depend on implemented tests and stay in Round 5.
This does not claim automated branch or condition measurement.

## Round 1a: Property tooling and row codecs

Add the test-only StreamData dependency, lock its release, and verify both CI
runtime combinations. Add test-side generators under `test/support` and properties
for the typed `VisitBudget`, `DepartureRequest` and `LiquidationPool` row codecs.
Keep property tooling out of application runtime dependencies and production
domain modules. Pair round trips with hand-authored row expectations.
Add independent missing-field and wrong-type tables, including explicit nils and
documented per-entity legacy defaults. Extend the same codec method to established
loan, auction, ship and account rows selected by the discovery matrix; a matching
encoder/decoder mistake must not make an invalid row look valid.

**Acceptance:** the existing suite passes with the locked dependency on both CI
runtimes. Codec properties detect a deliberate lost/changed semantic field and
produce a reproducible shrunk counterexample. Commit this before Round 1b.

## Round 1b: Input and notification contracts

Extend the current preset regressions into table-driven contract tests, starting
with presets and then company/ship names and player-supplied entity references.
Reuse data tables where rules are shared; keep command-specific expected errors
and identity semantics explicit.

Primary targets: `graded_books_test.exs`, `localization_test.exs`,
`use_cases/game_commands_test.exs`, and focused database contract tests.
Reuse Round 1a's generators for input properties.
Select established account, finance, trade and fleet commands from the discovery
matrix as well as presets. Include command-specific numeric boundaries and raw
LiveView event payloads whose list/map/nil values form serialization can hide.
For malformed input, require the declared safe error, a live sender process and
unchanged protected state, followed by a successful corrected request.

Implement the fuzzer's payload mode using the same command specifications that
Round 4 will use for sequences. Start from a valid command/fixture and mutate one
field or envelope rule at a time: omission, explicit nil/false, wrong scalar or
collection type, length/number boundaries, unknown/foreign/stale reference and
unexpected fields. Mark mutations as admitted or rejected with independently
expected results; an extra field is not automatically forbidden. Keep semantic
cases inside payload-envelope limits and test those limits separately.
Keep the mutation's intended rule violation and valid prerequisites explicit
during shrinking; do not let a smaller fixture fail an unrelated setup rule.

At the [application workflow](../lib/tijara_tides/use_cases/game_commands.ex),
use `GameCommands.run/6` with explicit test ports to exercise authentication,
payload validation and receipt behavior. It accepts a `CommandRequest` envelope;
its payload may be non-map for envelope-rejection cases. The server's command
handler requires a map and a bounded binary request ID, so test invalid transport
envelopes against their own declared response rather than assuming they reach
application validation. Use selected raw LiveView events for transport parsing.
Record which boundary each case exercises; a fake store cannot prove SQL safety.

### Valid browser-form contracts

Test legitimate submissions as well as malformed input. `LiveViewTest`'s form
helper collects form values but does not run the browser serializer. LiveView
1.2.11 emits `_unused_*` markers on changes; submission marks inputs used first.
Keep metadata-heavy raw submissions as a defensive admission contract.
Domain/application command fuzzing bypasses that conversion entirely. The instruction field-count regression
is a seed for this broader boundary, not its scope limit.

Inventory each command-producing form's submit event, variants, enabled fields,
hidden inputs, optional blanks, disabled omissions, UI-only fields, conversions
and receipt boundary. Check literal `phx-submit` declarations against the inventory;
dynamic declarations and command-producing events without forms need explicit
entries or exclusions. Record a named valid-submission test or a scoped exclusion
with its reason and follow-up round for every variant. Newly unclassified forms
fail inventory completeness. Share command identities and expected effects with
the fuzzer specifications, retaining a distinct web-event adapter.

Start with twelve valid-submission cases: instruction buy/sell; exchange
place/amend buy/sell; route add/update rule buy/sell; and borrowing/recasting.
Each case uses independently valid prerequisites and at most four submissions
covering its relevant optional fields, hidden defaults, disabled omissions and
untouched-input metadata. Submit representative raw events through `GameLive`
and the real command admission boundary. Assert the intended persisted business
effect and exact receipt replay, not merely a live process or the absence of an
internal error. A field-count rejection of a declared valid submission is a
failure, even though the same rejection is correct for an oversized API command.

Add two SQL-backed normalization properties, initially instruction and exchange
forms. Vary permitted browser metadata and equivalent numeric/minute formatting
while holding intended business inputs and request identity fixed. The baseline
must succeed; equivalent submissions must replay its receipt without another
effect, revision or extended deadline. Assert independently expected stored
amounts/durations too; agreement between two uses of the same faulty normalizer
is insufficient. Keep malformed semantic input in the separate rejection cohort.
Use five cases and twenty shrink steps per property, at most two submissions per
replay. Allocate a fresh world and server for every case and shrink attempt, with
cleanup in `after`, as required by Round 4's SQL replay rules.

Add two serial headless Chromium workflows using a pinned browser runner:
instruction buy/sell and exchange place/amend/cancel. Limit each to twelve
command submissions and sixty seconds. Drive actual controls, leave optional
fields untouched and exercise disabled-field omissions. Capture serialized field
shapes to check the raw-event fixtures against the actual LiveView client; the
fixtures must not be derived from the production command builder. Require the
expected persisted effect through disposable PostgreSQL. Use fresh browser
contexts/worlds and guaranteed server/browser cleanup; never use the local
playtest or deployed database. Add the runner and browser installation to local
and CI checks in Round 1b; missing browser setup must fail, not silently skip.
Record replayable input choices and sanitized serialization evidence without
session tokens or invitation credentials. Broader browser coverage remains
explicitly excluded until measured, rather than implied by SQL/LiveView tests.

### Rejections and notification contracts

For ordinary fuzz cases, unexpected raises, exits/throws, `:command_failed`,
`:internal_error`, storage failures or an unexpected halt/unavailable owner fail
the test. The workflow can rescue a planning exception into `:command_failed`,
so server liveness alone is insufficient. Injected-failure tests remain a
separate explicit cohort with their expected halt/recovery contract; never add
internal errors to a general allowlist of acceptable business rejections.

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
Maintain a reviewed test inventory under `test/support` of supported codes and
variants, mapping each to required arguments, a producer fixture and rendering
assertions. Add an ordinary-suite completeness test in `localization_test.exs`
that statically extracts current producer codes and compares that set with the
inventory's current codes. Fail on missing or stale entries, with source locations.
Keep supported legacy variants separate from the current producer set.

The existing localization test reads extracted gettext messages; those message
IDs are not a producer-code inventory. Scan domain producer ASTs, including
imported/qualified notice calls and structured effect payloads. Include literal
alternatives in conditional codes; an unresolved dynamic producer must fail with
its location and require an explicit, checked finite-code declaration rather than
being silently skipped. Run every inventory fixture and render assertion in both
locales, checking its declared arguments and distinctive expected values. A new
code must fail completeness until its contract is added; changed bindings must
fail the runtime assertions. Static completeness alone does not prove bindings
survived the allowlist.
Assert business reasons and localized numeric precision as part of the render
contract, including older notice producers, rather than checking only code and
placeholder completeness.

**Acceptance:** shared boundary cases detect the known name/identity errors;
domain-produced current lease expiry renders both rates and duration in both
locales, while the supported legacy row still renders its expected fallback.
Input properties produce reproducible shrunk counterexamples under a deliberate
fault. Adding an unregistered producer code fails inventory completeness, and
omitting a required binding fails its domain-produced render test.
The initial command specifications drive both valid examples and payload mutation
properties, with at most four initial payload properties, 50 cases each and 100
shrink steps per failure. They share the Round 1 input-property cohort rather than
adding a duplicate cohort. A deliberately rescued planner exception is detected
as a fuzz failure, and a malformed payload's safe rejection permits the next
valid command to succeed.
The form inventory classifies every discovered submit event and variant. The
twelve initial valid cases persist their intended effects; normalization
properties preserve receipt identity and independently expected terms. Both
browser workflows prove that raw-event fixtures reflect real serialization.
Deliberately forwarding `_unused_*` fields, retaining a converted UI-only expiry
field, or including raw numeric formatting in the fingerprint must fail the
intended contract. Restore each fault and confirm the same selection passes.

## Round 2: Deterministic lifecycle interaction tests

Add short, named scenarios to the existing domain suites before extending random
generation. Drive ordinary transitions through `Commands.execute/4` and
`Game.advance/3`; retain focused lower-level tests for individual transitions.
Primary targets are `route_funding_test.exs`, `warehouse_liquidation_test.exs`
and the existing freshness, weather and handling suites.
Extend established finance, guarantee, berth, market, identity and reporting
suites with the discovery matrix's missing boundaries and interactions.

| Scenario family | Variations to require |
|---|---|
| Funded repeating visit | Manual sail during an unfinished visit; pause then sail; resume; remove/change stop; failed departure; arrival and a second full visit |
| Accumulation handoff | Timeout then another claim in the same tick; cancellation/deletion; policy change; zero and partial accumulation; overdue bills; repeated unchanged retry |
| Award lease and receivership | Ordinary award resale versus liquidation-owned auction; bankruptcy before expiry, during grace and during liquidation; repeated full ticks through completion; a covered lease without a pool |
| Linked orders and purchases | Partial remote fill then departure, stop removal, Skip policy or lease expiry; completed goods retained while only unfilled demand and unused reservations release |
| Freshness and physical progress | Ordinary versus refrigerated aging around expiry; weather-delayed arrival crossing a shelf-life or visit deadline; handling already committed when expiry/liquidation starts |
| Finance and guarantees | Partial payment with protected funds; bid cancellation/refund with overdue bills; beneficiary bankruptcy then sponsor settlement; fixed grace deadlines and repeated settlement |
| Berths and fleet | Invalid queue head followed by eligible work; retry/cancel while capacity changes; reroute with settled fuel/canal costs; completion preserves committed handling |
| Established economy and accounts | Manufacturing constrained independently by inputs, funds and capacity; participation/replenishment with pre-existing stock; invitation/sign-in expiry, retry and quota recovery |
| Reporting and visibility | Loan/asset movement versus income; just-before/at/after period boundaries; history after bankruptcy; unrelated account/public views exclude private fields |
| Weather and receiving eligibility | Window-wide storm offsets; changing undisclosed weather cannot change a current quote; cached/frozen path survives catalogue edits; late perishable close followed by receiving aging |

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

Add work and publication assertions to selected traces: commits/broadcasts for
repeated owner activity, queue retries and unchanged queries; route partitions
across ticks; and reconciliation traversals as request, plan and instruction
counts vary independently. One table read does not rule out repeatedly scanning
its returned collection. Use deterministic operation counts for regression gates;
record machine-dependent timing separately when assessing broader runtime.

**Acceptance:** each family has a reachable success path, a rejection/wait path,
and an explicit cleanup or terminal-state assertion. Full-loop tests fail if a
reservation leaks or a lease is revived, even when no exception is raised.
Every discovery area has named applicable boundary/interaction evidence, including
the earlier-code scenarios; unsupported combinations have documented reasons.

## Round 3: SQL transition and recovery contracts

Run a small, selected set of Round 2 traces through real PostgreSQL, committing
and reloading after each accepted transition. Compare authoritative entities
with the expected domain result, accounting for documented codec defaults and
transient journal/lot buffers. Check targeted SQL rows and independent expected
cash/reservation deltas, plus `FinancialLedger.audit/2`.
Include selected earlier finance/guarantee and queue/trade traces, and load valid
established worlds with existing balances and history. Exercise actual migration
paths for supported older shapes where needed, rather than testing only empty
database creation or deleting fields from current rows.
Schema-migration fixtures need a separate scratch database and dedicated Repo
inside the disposable cluster. World IDs isolate rows, not schemas: never roll
back or replace the shared test Repo's schema while other tests use it. Keep
migration cases deterministic and separate from per-case property replays.

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
restart without changing deadlines or duplicating economic effects. Selected
earlier-code traces and historical fixtures preserve their independent expected
balances, ownership, pending work and derived state across recovery.

## Round 4: Stateful properties, command fuzzer and generated workflows

Keep the current eight trading seeds. Add the four state-guided scenario families
selected in the discovery scope, including finance/guarantees and
berth/trade/rerouting from earlier code. Each family should have a valid setup
prefix, explicit operation preconditions and a small set of
legal actions, plus deliberate invalid actions with known rejection contracts.
Use StreamData to generate bounded scenario parameters and symbolic action
sequences. Start from known-valid fixture states rather than generating arbitrary
world maps. Extend the current local `:rand` workflows separately where useful.
The deterministic skeletons ensure declared paths run; the command fuzzer also
explores model-valid combinations outside those skeletons. Both use the same
symbolic actions, backend adapters, invariant checks, shrinking and diagnostics.

### Command specification and exploration

Keep test-side command specifications under `test/support/command_fuzzer/`. Each
specification declares the command/action or variant, fixture prerequisites,
actor/ownership constraints, valid payload construction, targeted invalid
mutations and expected errors, symbolic references/results, model transition,
independent assertions and applicable milestones. The model chooses eligible
actions; do not ask the production admission predicate to decide what to generate.

Check the inventory against action branches in `Domain.Commands`, including
`locale` outside dispatch and the `buy`/`sell` alternatives in a bound action
variable. Account lifecycle APIs, ticks, queries, receipt replay and restart are
separate harness operations, not invented command action strings. Require every
discovered command variant to have a generator or an explicit scoped exclusion
with a reason and follow-up round. New unclassified actions fail inventory
completeness; unresolved dynamic dispatch requires a checked declaration. Record
generated, attempted, accepted, expected-rejected and skipped actions separately.

Start sequence exploration with the four selected families and established-world
fixtures containing two accounts/companies, existing balances and both free and
reserved resources. Run ordinary production commands after setup; fixture-only
capital grants or injected entities must not be counted as successful fuzz
commands. Combine families through their declared prerequisites, without
claiming all inventory commands are generated in the initial cohort.

Use an initial 80/20 selection weight for model-valid commands versus targeted
invalid mutations. Boundary ticks, wall-clock advances, observation queries,
receipt replay and restart are separate harness choices within the same action
limit; use at most one harness choice per three exploratory action slots so
command work is not crowded out. Cancellation and repeated commands come from
their command specifications. Only generate operations supported by the selected
backend, with unsupported operations visible in the inventory. The weight is an
exploration setting, not coverage evidence. Each initial exploration case must
attempt at least five model-valid non-observation commands and reach at least
one recorded resource acquisition plus release, transfer or completion milestone.
Track opportunities and shortfalls; insufficient eligible actions fail the
generator's progress check rather than passing as harmless ticks/rejections.
Keep the skeletons' stronger family-specific milestones too.
Construct the initial progress through a small model-valid prefix that stays
outside the shrinkable exploratory suffix. Count this prefix's command actions
within the fuzz action limit. Shrinking may reduce suffix diversity without
failing a new progress assertion; empty/model-invalid suffix actions are not
defects. An invariant failure during the prefix or before the progress milestone
still fails immediately and must not be discarded by a progress check.

### Backends, oracles and replay

The fast semantic backend executes `GameCommands.execute/4` and `Game.advance/3`
with explicit fixture accounts, catalogue, command context and a bounded test
lot allocator. It checks pure effects but does not claim authentication,
durable replay, SQL constraint or publication coverage. Payload/envelope and
receipt cases use the Round 1b `GameCommands.run/6` test-port backend. Selected web
contracts instead enter through `GameLive` and the Round 1b browser runner;
application/server command traces cannot claim browser serialization coverage.
Selected traces also run through an isolated `GameServer.command/4` SQL backend,
committing and reloading at checkpoints and exercising receipt replay and restart.
Never implement a second game engine or bypass command reconciliation by calling
individual mutation helpers inside the exploration loop.

Use symbolic identities for accounts, companies, ships, loans, lots and requests.
Bind actual IDs from results/state to those symbols separately for each backend;
preserve references across replay and shrink attempts. Replay means the same
symbolic action sequence and semantic expectations, not equality of generated
UUIDs or revision counts between a pure transition and a durable commit.
Control active time and wall time separately without sleeps; the server has an
injectable `wall_clock`, and deterministic ticks use test-side progression control.
Record fixture context, catalogue/weather settings and outcome-affecting seeds,
including auction valuation. Such seeds must be reproducible through fixture or
context injection; ID remapping alone does not reproduce random valuations.
If exact replay needs a narrow test seam at an existing boundary, implement and
verify it in this round rather than claiming the server already exposes it.

Check applicable independent contracts after every step: cash and reservation
deltas, debt/escrow, holdings and split lineage, eligible lot selection, physical
capacity, committed work, deadlines, owner/public visibility and economic effects
occurring once. Rejections preserve the protected state declared for that
boundary. Observation, receipt replay and restart have their own expected deltas;
account for documented recovery writes instead of asserting every revision is
unchanged. Persisted rows, receipts, ledger and publication/readiness assertions
belong to the SQL backend. Both backends retain independent expected facts;
agreement between them is supporting evidence only.

Retain the unexpected-error policy from Round 1b. SQL validity includes owner
readiness after commands and ticks, not just a returned reply. Keep explicit
storage-fault injection separate from ordinary discovery and retain its atomic
rollback/halt assertions. The per-case/per-shrink server cleanup rules below
apply to SQL fuzz traces too.

### Shared model and shrinking

The reference model tracks only the contract facts: selected stop and visit,
funds reserved/spent/released, accumulator identity and fixed deadline, and lease
or pool phase. It must not call production reconciliation predicates or copy the
whole simulation. Earlier-code families add only their relevant facts: outstanding
debt, protected funds, sponsor obligations, queue order, committed handling and
spent voyage costs. Resolve symbolic references such as `ship_a` and `current_stop`
against each fresh fixture. Check command preconditions and postconditions,
then compare model facts and independent invariants after every action.

For the initial lifecycle properties, use a scenario skeleton whose essential
setup and transitions cannot disappear during shrinking. Shrink amounts, clock
offsets and optional intervening actions first. Free-form sequence shrinking
needs dependency checks so removing a creator does not leave invalid references.
StreamData accepts any smaller input that still fails; it does not select a
particular semantic failure. Before executing each symbolic action, the runner
checks its preconditions against the independent model and resolves references.
If a removed prerequisite makes the action invalid, record it as skipped and do
not execute it or fail the property for that invalid action. A deliberate
rejection action has its own model preconditions and expected error; it still
runs when those preconditions hold. Never catch assertion failures or unexpected
command errors to convert them into skips: an action valid in the model that
fails in the system is a defect.

Keep essential skeleton transitions outside the shrinkable action list so skipped
optional actions cannot erase the triggering lifecycle path. Report skips and
the named failing invariant. Replay the minimized trace and verify that it still
reaches that path and violates the intended invariant; if it reveals a different
valid defect, preserve it separately and retain the original failure trace too.
These runner rules prevent unrelated precondition failures from becoming the
shrinker's smallest example; they do not promise failure-specific shrinking.

Check the Round 1–3 invariants after every action. Keep accepted-action progress
checks, but also require scenario-specific milestones: a handoff, a complete
return visit, partial fill and cancellation, or grace-to-liquidation-to-completion.
A high acceptance count from harmless ticks does not satisfy those milestones.
Earlier-code milestones include a partial payment and release, a beneficiary/
sponsor settlement, an actual queued admission, and a reroute or cancellation.
Specify applicable milestones per skeleton; do not require unrelated events in
every trace. Cross-company fixtures must assert both sides of a transfer.

Every failure must print seed, initial configuration, clock advances, commands,
replies and the failing invariant. Provide deterministic trace replay and
minimize failures into short checked-in regression scenarios. Minimized traces
must still reach the relevant state; dropping an operation and making every
remaining command reject is not a valid reduction.
Start every generated case and shrink attempt from a fresh fixture. The current
[database tests](../test/tijara_tides/infrastructure/game_persistence_test.exs)
commit real rows without an Ecto sandbox; their per-test `setup` server cannot
isolate multiple attempts inside one `check all`. Put SQL replay isolation inside
the property body/replay helper:

- Allocate a fresh world UUID for every case and shrink attempt. Seed its initial
  state independently of all prior attempts' rows and identities.
- Start that replay's own `GameServer` with `name: nil` and a unique supervised
  child ID, for example `{GameServer, world_id}` via `Supervisor.child_spec/2`.
  The module's ordinary child ID would otherwise collide within the same test.
- Enclose server use in `try`/`after` and call `stop_supervised(child_id)` in
  `after`, including when a failing assertion unwinds into the shrinker. Track
  the same child ID across restart checkpoints; verify successful termination.
  Arrange startup/cleanup so a failed start does not mask its original error.
- Keep only shared Repo startup and migrations in `setup_all`. Do not put replay
  server lifetime in `setup` or rely on test-end cleanup or a later action.
  Fresh world IDs fence retained rows; the disposable cluster removes them after
  the suite. Bound fixtures and shrink attempts to cap accumulated rows.

### Work limits and artifacts

Start with bounded fixed seeds in the ordinary suite and a few short SQL-backed
traces in the database suite. Offer a separate opt-in larger seed sweep; measure
runtime before widening the mandatory cohort. Reuse trace descriptions across
pure and SQL runners, keeping their persistence/publication assertions separate.
Keep fixed traces and shrinkable properties as separate mandatory cohorts:

| Cohort | Engine | Cases | Actions per case, at most | Shrink steps, at most | Suite |
|---|---|---|---|---|---|
| Existing trading workflows | Local `:rand`, fixed seeds | 8 traces | 90 | None | Ordinary domain |
| New fixed lifecycle traces | Local `:rand`, fixed seeds | 4 traces per selected family (4 families) | 60 | None | Ordinary domain |
| Fixed SQL lifecycle traces | Local `:rand`, fixed seeds | 2 traces per selected family (4 families) | 25 | None | Database |
| Input/codec properties (Round 1, including up to 4 fuzz payload properties) | StreamData/ExUnitProperties | 50 per property | Not an action sequence | 100 per failing case | Ordinary |
| Valid form contracts (Round 1b) | Raw LiveView events, fixed examples | 12 variants | 4 submissions | None | Database |
| Form normalization properties (Round 1b) | StreamData/ExUnitProperties | 5 per property (2 properties) | 2 submissions | 20 per failing case | Database |
| Browser serialization smoke (Round 1b) | Pinned Chromium runner | 2 workflows | 12 command submissions | None; 60 seconds per workflow | Browser with disposable database |
| Lifecycle properties | StreamData/ExUnitProperties | 20 per property | 30 | 100 per failing case | Ordinary domain |
| SQL lifecycle properties | StreamData/ExUnitProperties | 5 per property | 15 | 20 per failing case | Database |
| Broad command exploration (1 property) | StreamData/ExUnitProperties | 20 total | 30 | 100 per failing case | Ordinary |
| Selected SQL fuzz replays | Recorded symbolic traces | 2 total | 15 | None | Database |
| Extended command sweep (opt-in) | StreamData/ExUnitProperties | 100 total | 60 | 100 per failing case | Ordinary, opt-in |

Initially implement one lifecycle property and one SQL lifecycle property per
selected family: four of each. The discovery matrix records the selected
input/codec property count before implementation; measure that cohort before
adding properties. Per-property caps alone do not bound an unlimited property
inventory.
Round 1b's three web cohorts are additional bounded work, separate from ordinary
payload properties and Round 4 SQL traces. Record their runtime before adding
form variants or browser workflows.

The command fuzzer adds one mandatory broad sequence property: 20 cases, at most
30 actions and 100 shrink steps per failure in the ordinary suite. It reuses
Round 1b's payload properties and the four families' fixtures. Replay two selected
symbolic fuzz traces through PostgreSQL, at most 15 actions each, as deterministic
database regressions; they are separate from the eight fixed family SQL traces.
Do not automatically replay every pure case and every shrink attempt through SQL.
For a pure-discovered trace, establish a SQL baseline first where its contract
applies, then minimize separately within the SQL property budget if SQL behavior
is the failure. A boundary-specific discrepancy gets its own regression rather
than requiring both backends to fail identically.

Offer an opt-in larger command sweep with explicit case/action/shrink limits,
fixture sizes and a reported seed. Start at 100 cases, 60 actions and 100 shrink
steps, pure backend only, with a maximum of 50 exploratory corpus entries. Measure
before increasing the mandatory cohort or adding SQL sweeps; do not add an
unbounded background fuzzer or a coverage percentage gate.

The four fixed seeds per new family belong to `:rand`, not StreamData. StreamData
uses a reported ExUnit seed. Its case counts exclude fixed traces and shrink
replays. Action limits count generated slots, including skips. The fuzz progress
prefix counts within its action limit; fixture creation and the family skeletons'
mandatory setup have separate small fixture bounds. Every fixed trace and initial
lifecycle case must reach its declared milestones. The limits are work bounds,
not coverage claims. Use the same budgets locally and in CI, retain the existing
test timeout, and measure before widening; shrinking multiplies database work.

Failure output records the engine, its seed, initial configuration, symbolic and
resolved actions, skips, replies, failing invariant, Git revision and generator/
dependency versions. Save the original and minimized traces in
`cover/property-failures/<family>-<case>/`, which the existing always-uploaded CI
coverage artifact retains for 14 days. The Round 4 runner must write diagnostics
before re-raising the failure, without suppressing it. Promote confirmed minimized
counterexamples into checked-in regression fixtures under
`test/fixtures/property_regressions/`, with named tests and replay metadata.
A seed alone may stop reproducing after a generator or dependency changes.

Archive fuzz failures under `cover/property-failures/command-fuzzer/<case>/` using
the same original/minimized trace metadata and CI retention. Keep up to 50
deduplicated interesting traces in `cover/command-fuzzer-corpus/` for the bounded
opt-in run. Select interest by new command/state/milestone combinations declared
in the inventory, not an unmeasured claim of branch coverage. Store replayable
fixture/context descriptions, not live server objects or production credentials.
Promote confirmed failures to named tests and trace fixtures under
`test/fixtures/property_regressions/command_fuzzer/`; those fixed regressions run
without a seed search. Record corpus schema/generator versions and reject
incompatible entries visibly. Corpus admission, shrinking and diagnostic wrappers
must never swallow the failure they are saving.

**Acceptance:** fixed runs reach every declared milestone and can be replayed
exactly; rejected operations preserve protected state. Failure diagnostics are
sufficient to reproduce a sequence without rerunning a seed search.
Shrinking skips model-invalid actions without catching defects; the minimized
regression is checked for its lifecycle path and named invariant. Every SQL case
and shrink replay uses a fresh world and terminates its server even on failure.
Exercise cleanup with an intentionally failing replay, verify its server stopped,
then confirm a fresh replay starts from the expected initial state.
The required input/scenario categories have explicit coverage evidence alongside
randomized exploration, and failure traces are archived at the declared paths.
Both earlier-code families reach their declared milestones under the mandatory
cohorts; exploration is not confined to the review's reported failure paths.
The command inventory exposes exclusions, the broad fuzz property reaches its
progress milestones, and both selected SQL fuzz traces commit/reload and replay
without duplicate effects. Fault fixtures prove the fuzzer detects a violated
invariant and a rescued `:command_failed`; a payload defect and a sequence defect
each minimize to replayable named regressions. Unexpected halts are findings.

## Round 5: Mutation testing and detection matrix

Extend the bounded mutation/fault audit with one semantic fault for each recent
escape: grapheme counting instead of code-point counting; omitted rate binding
or wrong-key renderer clause; claims written before releases; omitted departure
budget release or visit-identity check; removed active-pool guard; unsafe name
or arbitrary preset identity admitted. Keep each fault isolated so the relevant
assertion fails after successful fixture setup, rather than detecting an
unrelated compilation or startup failure.
Include the later review mechanisms too: undisclosed future weather, lost frozen
paths, taking unqualified/reserved lots, permissive charge validation and defaults,
repeated scans/partitions, and unnecessary commits/broadcasts. Bound and select
curated cohorts explicitly; completion requires fault evidence for each known
mechanism, not necessarily every patch in one audit invocation.

Use isolated disposable checkouts, an unmutated baseline, exact patches and
explicit test selections including indirect callers. Retain failure evidence
and report survivors, invalid mutations, timeouts and selection misses separately.
Keep broad generated mutation testing opt-in as the existing pilot recommends.

Add a generated cohort around validation comparisons, Boolean guards, budget
arithmetic, deadline comparisons and lifecycle clauses. Start with at most 20
mutants per selected source and 60 per audit, one worker and a 30-second per-mutant
timeout, then measure before expanding. Curated patches remain a separate cohort.
Cap curated audits at 12 patches per invocation with the same worker/timeout
limits; split a larger fault catalogue across invocations and retain its evidence.
Include relevant property tests in the explicit test selection, with stable
seeds and bounded generation/shrinking so results can be repeated.

Select generated candidates independently of the recent diff. Reserve at least
half of the initial generated cohort for established behavior across at least
three areas, such as finance/guarantees, cargo/markets and accounts/identity.
Prefer guards, boundary comparisons, ownership checks, state transitions and
economic arithmetic with weak existing oracles. Record candidate selection and
code provenance in the discovery matrix; if an operator supplies too few valid
candidates, report the sampling shortfall rather than filling the cohort entirely
with recent fixes. The 60-mutant generated-audit cap covers both earlier and
recent candidates; curated patches retain their separate bounded cohort.

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
Include the bounded command-fuzzer properties with stable seeds in explicit
mutation selections. Report whether a fault was caught by a fixed regression,
family property or broad command exploration; a large number of fuzz executions
does not substitute for a detecting assertion.

For architecture and harness checks, use narrowly scoped fault fixtures too:
introduce a forbidden compiled dependency to prove the relevant guard detects it;
ensure the inventory includes newly relevant roots and transitive paths without
claiming the whole project graph is acyclic. Run instrumentation-sensitive tests
alone in a fresh VM and under the full suite; ensure tracing/cleanup does not rely
on another test loading a module or restoring shared state.

Expand the testing policy's scenario matrix with named tests for these contract
families and link the Round 0 checklist entries to the completed detection matrix.
The checklist already applies; only these evidence links wait for this round.
Implementing validated branch/condition instrumentation remains a separate
follow-up under the acceptance criteria in the testing policy.

**Acceptance:** every curated fault is detected by its intended assertion; the
restored baseline passes. The scenario matrix links concrete named tests, and
the ordinary fixed-seed and PostgreSQL cases run under existing local/CI checks.
The mutation report distinguishes missing generation from weak assertions and
selection failures, with all survivors triaged and exact replay evidence retained.
The report includes the stratified earlier-code cohort and its detection gaps,
not only historical bug reintroductions. Every selected discovery area has a
detecting fault or an explicit outstanding gap; a global score cannot hide one.

## Execution and completion

Apply Round 0 immediately, then implement Rounds 1a, 1b and 2–5 in order, committing
each after its focused tests and applicable normal checks pass. A documentation-
only round needs document/link and diff checks. Use `mix precommit` and
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

Completion means the discovery matrix accounts for all listed areas, every review
finding and both design decisions. Existing evidence is reused where sufficient;
selected gaps have named boundary/interaction tests and independent oracles.
The four generated families, including both earlier-code families, demonstrably
reach their required states; SQL/recovery checks verify durable results in fresh
and established worlds. The command fuzzer has a checked inventory, bounded
payload/sequence exploration, explicit unexpected-error detection and replayable
counterexamples, with selected SQL traces verifying the durable boundary.
The mutation audit explores earlier code as well as known
failure mechanisms and triages survivors by area. Remaining unselected exploration
is an explicit prioritized backlog, not a claim that latent bugs are exhausted.
Test count, line coverage and a global mutation score alone are not completion
criteria.
