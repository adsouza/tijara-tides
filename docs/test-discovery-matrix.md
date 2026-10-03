# Test discovery matrix

This is the initial Round 0 inventory for the [test expansion](test-expansion-plan.md).
Existing evidence below identifies checked-in tests, not complete coverage of an
area. Proposed exploration is not a claim that an undiscovered defect exists or
that an existing test lacks every listed assertion. Audit those assertions before
adding a scenario; reuse sufficient evidence and record the precise remaining gap.
All expansion work below is planned unless explicitly recorded as completed.

## Discovery across established and recent code

| Area | Existing named evidence | Proposed exploration and independent oracle | Candidate fault | Rounds |
|---|---|---|---|---|
| Finance and guarantees | `finance_test.exs`: protected funds cannot service debt; `guarantees_test.exs`: refundable pledge pays sponsor arrears before foreclosure | Two-company debt, pledge and bid-reservation sequences; calculate principal, accrued charges, escrow and released cash from fixture terms | Spend protected funds or settle sponsor loss twice | 1–5; generated family |
| Trading and auctions | `graded_books_test.exs`: unportioned claim releases only eligible lots; `auctions_test.exs` settlement cases | Partial fill/amend/cancel across companies and storage; compare actual released identities with independently eligible free batches; reconcile both sides | Take unfiltered lots or ignore another reservation | 1–5; queue/trade family |
| Fleet and berths | `port_berths_test.exs`: FIFO tickets survive repeated requests and invalid head; `rerouting_test.exs`: turning back retains position and spent fuel | Queue/handling/reroute/cancel sequences with capacity changes; expected queue order, retained committed work and settled costs | Release committed handling or reset spent fuel | 1–5; generated family |
| Port economy | `manufacturing_test.exs`: exact inputs/funds and output capacity; `participation_test.exs`: fractional production credits across ticks | Independent limits on ingredients, funds and output; reload existing inventory and replenishment credit; calculate recipe transformations and explicit economic sources/sinks | Ignore one production limit or reseed inventory on reload | 1–3, 5 |
| Accounts and identity | `email_identity_test.exs`: expired invite restores quota with active-clock expiry; `identity_history_test.exs`: compaction retains delivery/quota work | Cross-account misuse, expiry/retry and compaction of pending work; expected quota, token fencing and privacy from fixture ownership and clock rules | Check wrong clock/owner or delete pending work | 1–3, 5 |
| Reporting and queries | `reporting_test.exs`: revenue/cost totals and neutral asset transfers; period-boundary events | Hand-authored event totals and owner/public queries before/after restart; loans are liabilities, and each event belongs to its defined period | Count borrowing as profit or include a boundary event twice | 1–3, 5 |
| Storage, automation and weather | Route funding, warehouse liquidation, freshness and weather regression suites | Full phase collisions with explicit visit identities, receiver conditions, close times and known-weather cutoffs; preserve disclosed/frozen facts | Leak a visit budget, revive a pool or reveal future weather | 1–5; two generated families |
| Persistence and recovery | `game_persistence_test.exs`: ownership/restart and funding handoffs; `game_server_failures_test.exs`: rejected tick preserves prior clock/projection | Earlier finance and queue traces with valid historical fixtures; compare independent row/ledger expectations after replay, fencing and rollback | Default a required current field or publish an uncommitted projection | 1, 3–5 |
| Architecture and work bounds | `automation_architecture_test.exs`: compiled paths; `automation_cost_test.exs`: cached partitioning and instruction reads | Relevant root/dependency inventory, planted forbidden edge, independent population growth, commit/broadcast counts and fresh-VM test execution | Miss a back edge, rescan a collection or depend on prior module loading | 0, 2, 5 |
| Web form admission | `game_persistence_test.exs`: raw instruction buy/sell metadata and normalized-duration replay | Checked form/variant inventory; valid submissions with optional/hidden/disabled/untouched fields; independently expected persisted effects; actual browser serializer agreement | Forward browser metadata, retain converted UI-only fields or fingerprint raw formatting | 1b, 5 |

Test filenames in the first seven rows refer to `test/tijara_tides/domain/`.
Persistence/recovery tests are under `test/tijara_tides/infrastructure/`;
architecture tests are under `test/docs/`. The runtime phase inventory starts at
[Simulation](../lib/tijara_tides/domain/simulation.ex); command-triggered
reconciliation starts at [Commands](../lib/tijara_tides/domain/commands.ex).

The initial generated cohort has four families: finance/guarantees,
berth/trade/rerouting, route funding/linked orders, and award leases/receivership.
Other areas begin with named boundary/interaction tests and selected mutation
candidates. Generated coverage is not claimed for every inventory row. Record
the input/codec property count and cohort runtime before expanding the inventory.
The [command fuzzer](test-expansion-plan.md#command-specification-and-exploration)
reuses those families' specifications and adds bounded exploration across them.
Round 1b supplies payload mutations and an inventory of command variants and
entry points; Round 4 supplies one broad sequence property, selected SQL replay
and the corpus. Generators/exclusions, progress milestones and expected errors
must be recorded per command, including earlier commands outside the initial
four families. Undeclared command variants fail inventory completeness.
Classify web forms separately: application command coverage bypasses `GameLive`.
Round 1b adds twelve valid form variants, two normalization properties (five SQL
cases each) and two bounded Chromium workflows. These cohorts are implemented;
the existing instruction regression uses raw events, not browser JavaScript.
Other form variants require named evidence or scoped exclusions and follow-ups.

## Review findings as regression seeds

These fixes already have focused regressions. Extend their contracts during the
planned rounds rather than treating the historical bug list as the discovery limit.

| Review item | Existing regression location | Planned generalization |
|---|---|---|
| #1 Visit-budget lifetime | `route_funding_test.exs`, `game_persistence_test.exs` | Resource exit paths and recurring identities across lifecycle families |
| #2 Estate cover during liquidation | `warehouse_liquidation_test.exs`, `game_persistence_test.exs` | Irreversible phases with competing recovery/settlement paths |
| #3 Accumulator handoff write order | `game_persistence_test.exs` | Constraint-sensitive ownership transfers, IDs, insertion orders and rollback |
| #4 Preset name/identity admission | `graded_books_test.exs`, `game_persistence_test.exs` | Per-command ownership, typed references and domain/SQL admission agreement |
| #5 Owner activity writes | `dormancy_test.exs`, `game_persistence_test.exs` | Publication budgets and timer boundaries, including immediate warning cancellation |
| #6 Storm offset distribution | `weather_test.exs` | Deterministic broad-window samples and independent range/occurrence expectations |
| #7 Legacy voyage geometry | `game_persistence_test.exs` | Historical rows and frozen facts across catalogue changes/reload |
| #8 Lease notice bindings | `localization_test.exs` | Automatically checked producer inventory plus real-transition render fixtures |
| #9 Dependency cycle | `test/docs/automation_architecture_test.exs` | Complete relevant scope and deliberate guard-sensitivity faults |
| #10 Future quote information | `weather_test.exs` | Modifying undisclosed future facts leaves current observations unchanged |
| #11 Late perishable auction | `warehouse_liquidation_test.exs`, `game_persistence_test.exs` | Event-time settlement followed by receiver aging and exactly-once replay |
| #12 Tick/reconcile cost | `automation_cost_test.exs` | Count traversal work as populations grow independently, not just table reads |
| #13 Bankruptcy reason | `route_funding_test.exs` | Specific business reasons rather than successful fallback rendering |
| #14 Notice precision | `localization_test.exs` | Localized value/precision contracts across producers |
| #15 Malformed LiveView minutes | `game_persistence_test.exs` | Raw event payloads and recovery after rejection across established forms |
| #16 Filtered check/unfiltered take | `graded_books_test.exs` | Eligibility decisions constrain the exact identities later consumed |
| #17 Merchant reserved freshness | `graded_books_test.exs`, `market_transitions_test.exs` | Valid synthetic configurations exercise latent paths absent from today's catalogue |
| #18 Charges/estate and global defaults | `reservation_models_test.exs`, `persistence/game_rows_batching_test.exs` | Independent monetary splits; required fields, types and per-entity legacy omissions |
| Grace-rent decision | `warehouse_liquidation_test.exs` | Explicit accrued rent versus collected charges, including zero proceeds |
| Receiving-freshness decision | `cargo_freshness_test.exs`, `graded_books_test.exs`, `game_persistence_test.exs` | Equivalent eligibility under receiving conditions across purchase/collection paths |
| Instruction form field-count escape | `game_persistence_test.exs` | Valid web-form normalization across established commands; real browser metadata, optional fields and stable receipt fingerprints |

The persistence file above is under `test/tijara_tides/infrastructure/`; the batching
file is relative to that directory. Other unqualified filenames are domain tests
except `localization_test.exs`, which is under `test/tijara_tides/`.

## Evidence to record as implementation proceeds

For each selected contract, add the precise gap, named detecting test/property,
fixture and reachable milestones, independent expected facts, deliberate fault,
test selection, failure evidence and restored-baseline result. Record runtime and
generator budgets too. Distinguish existing evidence, newly implemented evidence,
unselected exploration and explicit limitations.
For command fuzzing, record attempted/accepted/expected-rejected/skipped actions,
the backend and boundary, fixture/context seeds, symbol bindings and readiness/
commit assertions. Unexpected `:command_failed` or halts are findings. Link fixed
counterexamples under `test/fixtures/property_regressions/command_fuzzer/` and
temporary failure/corpus artifacts to the exact replay and generator versions.

Round 5 adds measured fault evidence to this inventory. Stratify generated
mutations across earlier and recent code using the plan's shared audit cap;
report survivors and selection misses by area. Do not infer that an area is
covered merely from a high aggregate score. Newly discovered counterexamples
become checked-in regressions with replay metadata. Unselected work remains a
prioritized backlog, with no claim that completion proves absence of latent bugs.

## Round 1a evidence

`CodecPropertiesTest` adds seven properties (50 cases and 100 shrink steps each)
for visit budgets, departure requests, liquidation pools, loans, auctions, ships
and accounts. `Domain.CodecCases` supplies independent row facts, optional fields
and per-entity legacy defaults. Explicit examples cover zero, one and the signed
SQL integer maximum. Structural tables cover missing/unknown fields and malformed
row containers. These codecs intentionally preserve values; numeric/ownership
admission is verified at command and SQL boundaries in subsequent rounds.

StreamData 1.4.0 is locked and test-only. A mutation replacing encoded budget
remaining funds with zero fails the semantic-field property and shrinks amount
to 2, time to 0 and the optional flag to false; seed 12345 reproduces the same
example twice. Local baseline: 350 generated codec cases in about 0.1 seconds;
full `mix precommit` and disposable PostgreSQL coverage pass. The existing two
CI runtime pairs remain unchanged; their results are not claimed from this
local Elixir 1.20.4/OTP 29.1 run. Raw local receipts are under
`cover/test-expansion/round1a/`; CI continues uploading `cover/`.

## Round 1b evidence

`CommandPayloadPropertiesTest` has four properties (50 cases, 100 shrink steps)
and independent name, numeric and identity tables through `GameCommands.run/6`.
Unsafe company names and malformed UTF-8 hull names exposed latent admission
gaps; the domain now rejects them before a receipt or commit. Foreign existing
presets and unknown client IDs reject with the declared freshness error. A
rescued planner exception is explicitly a finding, never an allowed rejection.

`FormContractsTest` covers twelve instruction/exchange/route/finance variants and
two normalization properties (five fresh SQL worlds, 20 shrink steps each). It
checks independently expected persisted terms, exact replay, equivalent numeric
formatting, ready owners, SQL reload and failure cleanup. Each replay owns its
server inside `try/after`. The exchange handler now forwards only semantic fields.
The static form inventory classifies all 19 submit events; other variants remain
explicit exclusions. Sequence generators are marked planned until Round 4.

`BrowserContractsTest` runs two actual Chromium workflows: instruction buy/sell,
and exchange buy/sell/amend/cancel. It checks effects via SQL as well as captured
field names. LiveView 1.2.11 emits untouched `_unused_*` markers on changes and
marks inputs used before submission; disabled inputs are omitted. The raw tests
retain metadata-heavy submissions as a defensive contract. Browser tests have
their own runner/tag and are not selected by the ordinary database suite.

`NoticeInventoryTest` checks all 30 extracted producer codes against required
bindings and both locales, recognizes literal structured effects and rejects
unresolved dynamic producers. Checked forwarding seams remain explicit. Real
lease expiry/clearance and funding wait/timeout/departure transitions supplement
the synthetic renderer table; the table does not claim all producer paths ran.
Legacy notice coverage remains separate in `LocalizationTest`.

Six deliberate faults fail their intended selections and the restored baselines
pass: unsafe company input, preset grapheme counting, missing `grace_rate`, raw
instruction metadata, retained UI expiry and raw numeric fingerprints. Seed 12345
shrinks unsafe input to company/`a\0b`/empty prefix and preset count to 41.
The SQL normalization faults fail the valid-submission/receipt assertions rather
than passing on unchanged revision after a rejection. Patches, selections and
raw receipts are retained under `cover/test-expansion/round1b/`. CI uploads
coverage and browser evidence after both suites. The pinned Chromium workflows
take about five seconds locally; runtime-pair checks remain in CI.

## Round 2 audit and evidence

The audit retained existing scenarios where the assertions already supplied an
independent oracle. The following selected gaps now have full-phase or adjacent
boundary coverage; filenames below are under `test/tijara_tides/domain/`.

| Area | Audited sufficient evidence | Gap closed in this round |
|---|---|---|
| Repeating visits | `RouteFundingTest`: failed fuel limit preserves both budgets, manual departure refunds 200 and reserves inbound 300, paused and running variants | Arrival and return lap now use every simulation phase, preserving visit 2 and one reservation |
| Accumulation | Existing fixed-deadline partial accumulation and policy/repricing cases | New full-tick zero-balance handoff checks 149/150 ms, one active window and unchanged retry |
| Award/receivership | Existing ordinary resale actually invokes estate cover; no-pool extension control; exact rent/proceeds cap and sunk amounts | Active-pool resale, grace and completion now run full ticks rather than selected phases |
| Linked trading | Existing partial fill/handover, removed rule, Skip-owned collection, expiry and exact refund cases in `RouteFundingTest` | Reused; purchased identities and only unused reservations already asserted |
| Freshness/weather/handling | Existing receiving-rate tests, frozen paths, committed handling profiles and late-close receiver aging | New normal purchases in dry/reefer holds check expiry minus one/at/plus one and one writeoff; command-started storm crosses cargo and instruction deadlines before arrival, releasing its 200 budget |
| Finance/guarantees | Existing protected funds, partial payments, fixed grace, loss cap and refund-before-foreclosure | New command-driven pledge/restart/borrow/asset purchase/failure reaches sponsor settlement in a full zero-duration tick, asserts 5m loss exactly once and safe premature-bankruptcy rejection |
| Berths/fleet | `PortBerthsTest`: finite capacity queues without cash/cargo movement and full tick admits next work; invalid head/FIFO, owner cancellation and committed-work guards. `ReroutingTest`: exact settled costs and retained geometry | Reused independent intermediate assertions; generated combinations follow in Round 4 |
| Port economy | `ManufacturingTest`: exact stock/funds/capacity, one-input shortfall, persistent feedstock; `ParticipationTest`: fractional credits, coarse/fine equality and no production at zero participation | Reused; runtime SQL reload remains selected in Round 3 |
| Identity | Existing same-device retry, owner fences, quota compaction and undelivered work | New invitation/sign-in cases at deadline minus one/at/plus one vary the other clock independently and prove quota refunds once |
| Reporting/privacy | Existing neutral loans/assets, public-field exclusions, historical bankruptcy and period eligibility | New independently valued 100/200/300 events on adjacent quarter boundaries assert totals 100/500 and neutral borrowing |
| Work/publication | `AutomationCostTest`: one instruction read across independent request counts, cached partition once and equivalent forecasts; persistence owner activity/failure tests | Reused deterministic counters; fresh-VM guard sensitivity and durable publication checks follow in Rounds 3/5 |

Seven isolated faults fail and restored selections pass: missing departure
release, active-pool cover, late timeout/spoilage boundaries, zero sponsor loss,
shifted reporting period and wrong identity clock. The full tick assertions
observe independent quantities/deadlines rather than only exception absence.
Raw seed-12345 receipts and exact patches live in `cover/test-expansion/round2/`.
The focused domain selections run in under one second locally; normal full
checks retain the line gate. These scenarios supplement existing narrow helper
tests rather than changing production rules.

## Round 3 SQL evidence and constraint inventory

`Infrastructure.SqlTransitionContractsTest` is separate from the large gameplay
persistence suite. Its 32 handoff combinations vary update/delete, existing/new
claimants, both lexical ID orders, fixture insertion order, and zero/100-cent
accumulation. These are typed adapter fixtures using the owning automation root;
they prove immediate-index ordering, not departure-policy eligibility. Full-tick
eligibility and timeout remain the Round 2 scenarios and existing server tests.
Every valid handoff checks the active SQL row/deadline, constant cash/reservation
and ledger audit. Two active zero-balance claims require rollback of all rows,
revision, journal and receipt.

The same module runs ordinary server borrowing/repayment through exact receipt
replay, reload and restart with independent principal/cash/profit expectations;
queued buy/cancel preserves committed work and progresses the next eligible ship.
A budget CHECK violation rolls back otherwise balanced money movement. A real
lot writer case spans the 60,000-bind limit: 8,572 rows, conserved children on
both sides of the chunk boundary, and a late CHECK failure rolling back both
statements. It complements the counting double rather than replacing it.

| Immediate/deferred constraint | Applicable transfer and evidence |
|---|---|
| `game_one_departure_accumulator`, immediate partial unique | New 32-case release/claim matrix and invalid zero-balance pair |
| Visit-budget remaining/amount CHECK; departure accumulated/required CHECK | New balanced-money rollback; existing unbacked-release persistence regression and typed model bounds |
| Guarantee beneficiary partial unique | Existing durable sponsor approval/release/default test; rows close by status, they are not deleted by normal settlement |
| Ship company/name unique | Existing ship-name migration and durable rename tests; no live ship-name swap command, so simultaneous swaps are excluded |
| Lot parent FK and deferred split conservation/holding checks | New cross-chunk conserved parent/children and late rollback; existing cargo-machine-ID migration checks incompatible lineage |
| Warehouse/order/route ownership FKs and backing checks | Existing mixed-stage liquidation rollback, linked-order unbacked release, closed bid/expired lease and market-CAS rollback tests |
| Market version compare-and-swap | Existing stale stock/budget rollback and owner progression conflict-reload tests |

Historical `RelationalStorageTest` replays now allocate a separate scratch
database and dedicated Repo per case and drop it afterwards. The shared gameplay
Repo schema is never rolled back. Existing fixtures exercise actual JSON-to-row
migrations, duplicate-name repair, lot-sequence counters, guaranteed-loan links,
cargo-machine-ID lineage, immutable postings and receipts, with reversible
snapshots and malformed-history rejection.

The existing persistence tests also retain mid-visit budget replay, mixed-stage
liquidation recovery, manufacturing stock/budget reload, invitation quota/fencing,
frozen legacy voyage paths, owner-visit coalescing and uncommitted-publication
rejection. Their exact assertions were audited rather than copied into the new
module. Failure doubles and ordinary discovery remain separate. SQL comparisons
use the prior durable snapshot where codec omissions/defaults differ from memory.
Raw focused/full receipts and fault patches are in `cover/test-expansion/round3/`.

Sensitivity: claims-before-release fails the valid handoff commit with the named
partial index; dropping one row only in a large lot batch reaches the final SQL
count assertion (8,571 instead of 8,572). Restored selections pass. An unscoped
lot-drop experiment broke world startup and is classified as setup failure, not
an assertion kill. Focused SQL/migration checks take about six seconds locally;
full SQL verification passes with 949 tests and 93.88% line coverage.

## Round 4 executed cohort

`LifecycleFuzzerTest` uses four fixed `:rand` traces per family (60 actions),
plus four StreamData properties (20 cases, 30 actions, 100 shrink steps).
`SqlFuzzerTest` uses two fixed traces per family (25 actions), four SQL
properties (five cases, 15 actions, 20 shrink steps), and two broad SQL replays.
`LifecycleFuzzerTest` also runs the broad 20-case command property. Each prefix
requires five accepted commands and the declared economic milestones; ticks,
fixture grants and skipped dependencies do not satisfy command progress.

| Family | Independent facts and required path | Deliberate detection evidence |
|---|---|---|
| Finance and guarantees | Borrowing is cash and debt, not profit; partial principal payment; beneficiary restart; sponsor escrow acquisition followed by release or capped claim | Existing finance/guarantee regressions; Round 2 zero-loss fault; runner rejects wrong cash deltas |
| Berths, trade and rerouting | Actual queue admission, duplicate rejection, cancellation without movement, committed handling, return after reroute with cargo retained | Queue milestones in both backends; independent quantity/port checks after deadlines |
| Route funding | Configured budgets, rejected underfunded departure, release on manual departure, full return lap and new visit identity | Conservation after every action; return visit must have exactly its configured amount and visit 2 |
| Leases and liquidation | Ordinary lease/purchase/store, expiry, grace, estate transition, auction clearance and completion | Fixed grace deadline and independently calculated reference proceeds, charges and estate sink |
| Broad commands | Model-valid debt acquisition/payment/release, followed by generated combinations and independently declared violations | `FuzzerContractTest`: unbacked reservation, real rescued planner error, shrunk preset lifetime fault |

The model deliberately does not duplicate interest scheduling, NPC price curves
or auction settlement. Those retain independent named tests from Rounds 2–3.
The route skeleton selects the complete-return-visit milestone. Linked partial
fills/handoffs retain the named `RouteFundingTest` and SQL regressions; generating
linked exchange counterparts is the next sequence-cohort extension. It is not
claimed by the current route generator.

`CommandInventoryTest` checks every dispatch action, route operation and literal
form event. `Inventory.command_contracts/0` records sequence generators, boundary
contracts and exclusions with follow-ups. Pure replay/restart are unsupported and
recorded as skips; SQL runs actual receipt/recovery checkpoints. Each SQL replay
and shrink attempt starts a fresh UUID world and stops its child in `after`,
including a deliberately failing replay followed by a clean new case.

Versioned original/minimized diagnostics include symbolic and resolved actions,
replies, clocks, invariant, seed, source revision, generator/fixture versions and
valuation seed under `cover/property-failures/`. They contain no session tokens.
The optional corpus keeps at most 50 declared semantic-interest combinations;
these are not branch coverage measurements. Historical payload and runner
sensitivity fixtures live in `test/fixtures/property_regressions/command_fuzzer/`.

Round 4 local receipts: `mix precommit` passes 857 tests/properties; disposable
PostgreSQL coverage passes 974 with 94.00% line coverage in 48.8 seconds, and
both browser workflows pass in 4.4 seconds. No compiler warnings occurred.
The focused ordinary cohort takes 3.7 seconds; SQL traces/properties take about
12 seconds without coverage. The opt-in 100-case sweep plus corpus replay passes
in 0.8 seconds on this host. These are local measurements, not CI promises or
measurements for the two CI runtime pairs. Raw logs are under
`cover/test-expansion/round4/`.

## Round 5 detection matrix

The [audit report](mutation-audit.md) explains selection, limits, provenance and
initial survivors. The checked-in [compact results](../test/fixtures/mutation_faults/results.json)
record each exact patch hash, detecting test, initial classification and 0/2/0
baseline/mutant/restoration exits. Full raw receipts are under
`cover/test-expansion/round5/`. These are scoped sensitivity results.

| Fault | Review / discovery contract | Detecting test or property (first failure; all retained in results) |
|---|---|---|
| `unsafe-company` | #4 / earlier naming | property forbidden name characters reject without committing and a corrected request succeeds (TijaraTides.UseCases.CommandPayloadPropertiesTest) |
| `preset-graphemes` | #4 | property combining marks count independently of bytes and control-free name limits (TijaraTides.UseCases.CommandPayloadPropertiesTest) |
| `notice-binding` | #8 | test actual lease expiry carries both rates and grace through the renderer, then clears once (TijaraTides.NoticeInventoryTest) |
| `metadata-forwarded` | Instruction form escape | test valid instruction_sell form commits its intended terms and exact replay (TijaraTides.Infrastructure.FormContractsTest) |
| `raw-expiry` | #15 / form escape | test valid instruction_sell form commits its intended terms and exact replay (TijaraTides.Infrastructure.FormContractsTest) |
| `raw-number` | Form normalization | test valid instruction_sell form commits its intended terms and exact replay (TijaraTides.Infrastructure.FormContractsTest) |
| `visit-release` | #1 | test manual departure mid-visit releases only that visit's cash, including after pausing (TijaraTides.Domain.RouteFundingTest) |
| `pool-cover` | #2 | test receivership auction cover cannot revive an award lease with an active liquidation pool (TijaraTides.Domain.WarehouseLiquidationTest) |
| `timeout-boundary` | Funding deadline | test one oldest request accumulates, times out at a fixed deadline, and enters cooldown (TijaraTides.Domain.RouteFundingTest) |
| `spoilage-boundary` | Cargo deadline | test ordinary and refrigerated purchases cross exact spoilage boundaries without repeated writeoffs (TijaraTides.Domain.GameTest) |
| `guarantee-loss` | Earlier finance | test commands and a full unchanged tick settle beneficiary failure on sponsor books exactly once (TijaraTides.Domain.GuaranteesTest) |
| `report-boundary` | Earlier reporting | test events exactly at a boundary belong to the new period (TijaraTides.Domain.ReportingTest) |
| `identity-clock` | Earlier identity | test expired invite restores quota and expiry uses the active clock (TijaraTides.Domain.EmailIdentityTest) |
| `claims-before-release` | #3 | test accumulator release precedes claims across release shape ID order insertion and zero balance (TijaraTides.Infrastructure.SqlTransitionContractsTest) |
| `lost-lot-row-large-batch` | SQL chunk boundary | test lot parent and conserved children span the bind-limit chunk and a late failure rolls both chunks back (TijaraTides.Infrastructure.SqlTransitionContractsTest) |
| `arbitrary-preset-id` | #4 | property preset client references cannot create identities or edit foreign identities (TijaraTides.UseCases.CommandPayloadPropertiesTest) |
| `future-weather` | #10 | test the current storm does not disclose the next three storms on a long route (TijaraTides.Domain.WeatherTest) |
| `narrow-weather-offset` | #6 | test staggered storms span the full period deterministically without changing occurrence (TijaraTides.Domain.WeatherTest) |
| `repeat-weather-partition` | #12 | test a legacy sailing path is partitioned once, then cached across ticks and serialization (TijaraTides.Domain.AutomationCostTest) |
| `filtered-check-unfiltered-take` | #16 | test forced exchange fills take fresh eligible lots and leave older cargo behind (TijaraTides.Domain.WarehouseLiquidationTest) |
| `merchant-reservations` | #17 | test one unit beyond an 80-unit merchant reservation is refused (TijaraTides.Domain.PortCargoMarketAggregateTest) |
| `permissive-charges` | #18 | test completion rejects forged charges, clocks and estate classification (TijaraTides.Domain.ReservationModelsTest) |
| `required-defaults` | #18 | test fields with domain defaults must come from the domain codec, not the adapter (TijaraTides.Infrastructure.Persistence.GameRowsBatchingTest) |
| `owner-redundant-commit` | #5 | test repeated owner visits do not commit or broadcast within the same minute (TijaraTides.Infrastructure.GamePersistenceTest) |
| `compiled-back-edge` | #9 | test ShipWorld has no transitive workflow back edge, including adapters outside the service inventory (TijaraTides.AutomationArchitectureTest) |
| `lost-frozen-path` | #7 | test turning back releases fuel and retains the current position and spent fuel (TijaraTides.Domain.ReroutingTest) |
| `late-perishable-close` | #11 | test late ticks settle perishable liquidation at the close before aging in the buyer's storage (TijaraTides.Domain.WarehouseLiquidationTest) |
| `repeat-instruction-scan` | #12 | test funding revalidation reads the instruction table once for one or many requests (TijaraTides.Domain.AutomationCostTest) |
| `wrong-bankruptcy-reason` | #13 | test receivership stops departure with its own reason rather than a duration error (TijaraTides.Domain.RouteFundingTest) |
| `notice-precision` | #14 | test weather notices format fractional minutes to one localized decimal (TijaraTides.LocalizationTest) |
| `receiving-aging` | Receiving-freshness decision | test cooling cannot revive spoiled cargo and ordinary holds accept perishables (TijaraTides.Domain.CargoFreshnessTest) |
| `grace-rent` | Grace-rent decision | test a late rent tick does not charge both grace and liquidation rates for the same time (TijaraTides.Domain.ReservationModelsTest) |

The generated cohort contains twenty candidates per area: finance, markets and
accounts. Of sixty changed lines, 57 predate `5ad0399` (20 finance, 17 markets,
20 accounts). Initial results were 45 detections, two selection misses and
thirteen full-applicable survivors. Every survivor received an exact SQL-inclusive
triage, a fixed counterexample/general contract and an exact detecting replay.
The compact results link all sixty indices to their actual failed assertions,
with provenance and initial/full-scope/replay outcomes kept distinct.

| Discovery area | Deliberate evidence | Outstanding scoped exploration |
|---|---|---|
| Finance and guarantees | Twenty loan-action mutants; zero sponsor-loss fault | More generated interest/arrears clauses |
| Trading and auctions | Independent price/capacity properties; eligible identity and reservation faults; late-close fault | Generated linked-order counterpart and partial-fill sequences |
| Fleet and berths | Frozen-path fault; existing queue and committed-work scenarios plus generated family | Additional queue-admission source mutants |
| Port economy | Existing independent recipes/credits and SQL reload assertions; merchant backing/reservation mutations | Manufacturing/participation source mutations are unselected in this cohort |
| Accounts and identity | Quota/type/suspension/earnings properties; wrong-clock fault | More compaction and ownership clauses |
| Reporting and queries | Shifted period fault; independently valued totals and privacy checks | Generated report/projection decisions |
| Storage, automation and weather | Full lifecycle faults; long-voyage disclosure and independent rent properties | Broader interacting weather/handling parameter sequences |
| Persistence and recovery | Real unique-index ordering, chunk loss and required-default faults | Further supported migration shapes and competing transfers |
| Architecture and work | Compiled back edge, repeated scans/partitions, redundant owner commit | Validated branch/condition instrumentation remains separate |
| Web forms and notices | Raw metadata/expiry/fingerprint faults, binding/precision inventory | Remaining variants stay explicit in the form inventory |

Mutation discovery added seven properties and ten named examples. They run in
ordinary local/CI checks; mutation generation remains opt-in. The two-candidate
named-only comparison detects asking-price reversal with a fixed example, while
bidding-price reversal requires the varied price property in that selection.
No aggregate score replaces the remaining gaps listed above.

Final local verification: 874 tests/properties pass in precommit, 991 pass with
disposable PostgreSQL and 94.01% line coverage, and both browser workflows pass.
Precommit and SQL compilation produce zero compiler warnings. Detailed runtime
measurements and artifact paths are in the audit report; the two configured
Elixir/OTP combinations still require CI execution.
