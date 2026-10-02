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
cases each) and two bounded Chromium workflows. These are proposed cohorts;
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
