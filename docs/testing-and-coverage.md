# Testing and coverage

Run `scripts/check-local.sh` for the same local checks used by the pre-push hook.
Its disposable PostgreSQL run includes all Elixir tests and line coverage. The
check also reports desktop JavaScript helper line, branch and function coverage.
CI runs the same commands and uploads reports as artifacts for each runtime or
platform, including when a test or coverage threshold fails.

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
| Departure and privacy | Cancel waiting remainders and incompatible plans; owner-only visibility |

The database/browser integration test additionally exercises UI submission and
preserved drafts, command replay, cancellation, automatic arrival settlement,
SQL reload and a single financial posting after restart.

## Server failure scenarios

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
