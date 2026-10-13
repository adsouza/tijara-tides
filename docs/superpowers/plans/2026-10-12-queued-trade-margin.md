# Queued Trade Margin Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a manual port trade that must be queued carry a player-approved
price margin (0–10%, default 2%), asked once per trade or saved per side.

**Architecture:** The server alone decides that a trade will queue.
`BerthAllocation.submit/4` refuses a queue-bound trade that carries no margin
and has no saved default with `:queue_margin_required`; the LiveView answers
that error with a dialog and resubmits the retained command with the margin.
`Trade.queued_limit/3` is the single arithmetic for the widened limit. Defaults
live on the account row, owned by `AccountWorld`.

**Tech Stack:** Elixir, Phoenix LiveView, PostgreSQL (Ecto migrations), ExUnit,
Gettext.

**Spec:** `docs/superpowers/specs/2026-10-12-queued-trade-margin-design.md`

## Global Constraints

- Margin: integer basis points 0..1,000; slider 0–10% in 0.5% (50 bps) steps,
  default 2% (200 bps).
- Manual trade `limit`: integer 0..1,000,000,000,000 (`Prices.max_cents/0`).
- Buy widened limit: `min(max_cents, div(limit * (10_000 + bps) + 9_999,
  10_000))`. Sell: `div(limit * (10_000 - bps), 10_000)`.
- Absent optional fields stay absent in transport payloads; defaults apply in
  dispatch.
- Admission precedence unchanged: integers beyond bigint →
  `:command_value_invalid`.
- Errors: malformed trade options → `:invalid_trade`; malformed `queue_margin`
  → `:invalid_queue_margin`; missing margin → `:queue_margin_required`.
- No raise or constraint reachable from tick/commit; domain validates with the
  database constraint's bounds.
- Zero compiler and test warnings. Never run `mix gettext.merge`.
- Each new guard is broken once to confirm a test fails.

## Review Focus

1. A sell queued with a crafted `destination` (U+0000, a map) must queue
   without storing it — pinned in Task 3.
2. An old-style trade payload (no new fields) retried with its request id must
   replay, not conflict — pinned in Task 5 (handler leaves fields absent).
3. Selecting another ship while the dialog is open must not retarget the
   confirmed trade — pinned in Task 5.
4. Resetting one side's default must leave the other side's value — pinned in
   Task 6.
5. A ceiling-sized buy limit with a 10% margin must store exactly the ceiling,
   never overflow — pinned in Task 1 and Task 4.

---

### Task 1: Price ceiling and margin arithmetic

**Files:**
- Create: `lib/tijara_tides/domain/prices.ex`
- Modify: `lib/tijara_tides/domain/trade.ex`
- Test: `test/tijara_tides/domain/trade_test.exs` (create)

**Interfaces:**
- Produces: `Prices.max_cents() :: 1_000_000_000_000`;
  `Trade.max_margin_bps() :: 1_000`;
  `Trade.queued_limit(side :: "buy" | "sell", limit :: 0..max_cents,
  margin_bps :: 0..1_000) :: non_neg_integer`;
  `%Trade{margin_bps: nil | integer, save_margin: boolean}` (defaults
  `nil`, `false`).

- [ ] Write failing tests: buy/sell at 0, 50, 200, 1,000 bps; odd-cent rounding
  (buy 101 cents at 200 bps → 104 (103.02 rounds up); sell 101 at 200 → 98
  (98.98 rounds down)); `queued_limit("buy", 1_000_000_000_000, 1_000) ==
  1_000_000_000_000`; `queued_limit("sell", 0, 1_000) == 0`.
- [ ] Run `mix test test/tijara_tides/domain/trade_test.exs` — FAIL (undefined).
- [ ] Implement `Prices` and `Trade.queued_limit/3` with integer arithmetic only.
- [ ] Run tests — PASS. Mutate the `+ 9_999` and the `min` once each; confirm a
  failure; restore.
- [ ] Commit.

### Task 2: Account defaults, storage and the `queue_margin` command

**Files:**
- Create: `priv/repo/migrations/20261013000000_add_queue_trade_margins.exs`
- Modify: `lib/tijara_tides/domain/account.ex`, `account/rows.ex`,
  `account_world.ex`, `commands.ex`,
  `lib/tijara_tides/use_cases/command_payload.ex`,
  `lib/tijara_tides/infrastructure/persistence/game_rows.ex`,
  `lib/tijara_tides_web/components/game/presentation.ex` (error text),
  test fixtures that build account rows (`test/support/properties/codec_cases.ex`,
  `test/support/command_fuzzer/specs.ex`, `relational_storage_test.exs`, others
  found by `grep -rln '"locale" =>' test`).
- Test: `test/tijara_tides/domain/account_aggregate_test.exs`,
  `test/tijara_tides/infrastructure/game_persistence_test.exs`

**Interfaces:**
- Consumes: `Trade.max_margin_bps/0`.
- Produces: `%Account{queue_margin_buy_bps: nil | 0..1000,
  queue_margin_sell_bps: nil | 0..1000}`;
  `Account.set_queue_margin(account, side, bps) :: {:ok, account} | {:error,
  :invalid_queue_margin}`;
  `AccountWorld.set_queue_margin(state, account_row, side, bps) :: {:ok, state,
  %{}} | {:error, :invalid_queue_margin}`;
  `AccountWorld.queue_margin(state, account_id, side) :: nil | 0..1000`;
  command `%{"action" => "queue_margin", "side" => side, "margin_bps" => bps}`.

- [ ] Failing domain tests: set buy 200, set sell 0, clear buy with `nil` keeps
  sell; refuse side `"hold"`, bps −1, 1,001, 2.0, `"200"`, `true`.
- [ ] Implement struct fields, `set_queue_margin/3`, `AccountWorld` functions,
  `Commands` clause `%{"action" => "queue_margin"}` (missing `margin_bps` key is
  invalid; present `nil` clears), admission `"queue_margin" => ~w(side
  margin_bps)`, error text for `:invalid_queue_margin`.
- [ ] Migration: two nullable `integer` columns with `CHECK (... BETWEEN 0 AND
  1000)`; `down` drops both.
- [ ] Codec: add both to `Account.Rows` `@fields` (exact-key check), `GameRows`
  column mapping and `@required["accounts"]`.
- [ ] Update every account-row fixture to carry both keys (`nil`).
- [ ] Database test (script cluster): set via `GameServer.command`, reload,
  read back both values including `nil`; a row missing a key raises before SQL
  in `GameRows` (unit test on the binder).
- [ ] Fuzzer spec for `queue_margin`. Run `mix test` on touched files and
  `python3 scripts/test-game-db.py` for persistence.
- [ ] Mutate the 0..1000 guard once; confirm failure. Commit.

### Task 3: Trade command contract

**Files:**
- Modify: `lib/tijara_tides/use_cases/command_payload.ex`,
  `lib/tijara_tides/domain/commands.ex`,
  `lib/tijara_tides/domain/services/trade_settlement.ex` (limit ceiling)
- Test: `test/tijara_tides/domain/trade_command_test.exs` (create),
  `test/tijara_tides/use_cases/command_payload_test.exs`

**Interfaces:**
- Consumes: `Prices.max_cents/0`, `Trade.max_margin_bps/0`, new `Trade` fields.
- Produces: `buy`/`sell` admit `margin_bps`, `save_margin`; dispatch builds
  `%Trade{margin_bps, save_margin}`; sells get `destination: nil`; buys require
  a catalogue port id string, else `:purchase_destination_required`.

- [ ] Failing tests: invalid `margin_bps` (−1, 1,001, 2.5, `"200"`), invalid
  `save_margin` (`"true"`, 1), `save_margin: true` without `margin_bps` →
  `:invalid_trade` with state unchanged; bignum margin via `GameCommands.run`
  → `:command_value_invalid`; limit 1,000,000,000,000 admitted, +1 refused;
  queued sell with destination `"A\u0000"` stores `pending_destination: nil`;
  buy with destination `"A\u0000"`, `%{}`, `"Atlantis"` refused.
- [ ] Implement option validation in `Commands` (before calling submit) and
  the limit ceiling in `TradeSettlement.trade/…` validation.
- [ ] Run tests — PASS. Mutate the destination discard; confirm failure.
  Commit.

### Task 4: Margin resolution at queue time

**Files:**
- Modify: `lib/tijara_tides/domain/services/berth_allocation.ex`
- Modify existing tests that queue manual trades: `port_berths_test.exs`,
  `game_test.exs`, `trade_offers_test.exs`, `game_persistence_test.exs`,
  `control_sweep_test.exs`, `ship_world_test.exs` as needed.
- Test: `test/tijara_tides/domain/queue_margin_test.exs` (create)

**Interfaces:**
- Consumes: `Trade.queued_limit/3`, `AccountWorld.queue_margin/3`,
  `AccountWorld.set_queue_margin/4`.
- Produces: `submit/4` returns `{:error, :queue_margin_required}` for a
  queue-bound trade without margin or default; stores widened `pending_limit`.

- [ ] Failing tests, for both queue paths (ship `loading`; berth busy via
  `BerthAllocation.enqueue` of another ship and `berth_count: 1`):
  no margin/no default → `:queue_margin_required`, state identical; explicit
  200 → `pending_limit == queued_limit`; saved default applies; explicit
  overrides default; `save_margin` stores default in the same result state;
  immediate execution ignores margin but `save_margin` still saves; sell side
  uses the sell default only.
- [ ] Contract test: queue a buy at margin m; raise the ask to exactly the
  widened limit (stock reduction via `PortCargoMarketWorld`) → `advance/2`
  fills; one cent more (or one stock step above) → stays pending. Same for a
  sell's bid.
- [ ] Implement `resolve_margin/3` and `queue/4` helpers inside
  `BerthAllocation`; read the default from state (`AccountWorld.queue_margin`)
  not from the passed account map.
- [ ] Update existing queue tests to pass an explicit margin that keeps their
  assertions (usually `margin_bps: 0`).
- [ ] Run the full `mix test`. Mutate (a) skipping the refusal, (b) using the
  unwidened limit; confirm failures. Commit.

### Task 5: Dialog and resubmission (LiveView)

**Files:**
- Create: `lib/tijara_tides_web/components/game/queue_margin_dialog.ex`
- Modify: `lib/tijara_tides_web/live/game_live.ex`,
  `lib/tijara_tides/use_cases/game_queries.ex` (`queued_limit/3` delegate),
  `assets/css/app.css` only if the picker's backdrop classes cannot be reused.
- Test: `test/tijara_tides_web/queue_margin_dialog_test.exs` (create)

**Interfaces:**
- Consumes: `:queue_margin_required`, `GameQueries.queued_limit/3`.
- Produces: assign `queue_margin_prompt :: nil | %{command: map, margin_bps:
  integer, save: boolean}`; events `queue-margin-change`, `queue-margin-confirm`,
  `queue-margin-cancel`.

- [ ] Failing LiveView tests: submitting a buy while the ship is loading opens
  the dialog (no error flash); confirm at 2% queues with widened limit; Cancel
  and Escape queue nothing; changing slider updates the worst-case text;
  selecting another ship while open then confirming queues on the original
  ship; a confirm event with no prompt is ignored; the ordinary trade payload
  contains no `margin_bps`/`save_margin` keys.
- [ ] Implement: in `run/2`'s error branch, `:queue_margin_required` assigns
  the prompt with the exact command sent (including `request_id`) instead of a
  flash. Confirm handler adds parsed `margin_bps` and, only if ticked,
  `save_margin => true`, then calls `run/2` with that map and clears the
  prompt. Dialog markup follows `DestinationPicker` (focus_wrap, role=dialog,
  Escape, click-away).
- [ ] Run tests — PASS. Commit.

### Task 6: Trade panel default control

**Files:**
- Modify: `lib/tijara_tides_web/components/game/ports_panel.ex`,
  `lib/tijara_tides_web/live/game_live.ex`
- Test: `test/tijara_tides_web/queue_margin_dialog_test.exs`

**Interfaces:**
- Consumes: `view.private["account"]["queue_margin_buy_bps"|"..._sell_bps"]`.
- Produces: events `queue-margin-save` (`side`, `margin_bps` form) and
  `queue-margin-reset` (`phx-value-side`), each sending `queue_margin`.

- [ ] Failing tests: line shows "Ask me" / "2.0%"; saving buy 300 stores 300;
  reset buy sends `nil` and keeps sell's value; after saving, a queued buy
  opens no dialog while a queued sell still does.
- [ ] Implement the compact line and per-side editor. Run tests. Commit.

### Task 7: Copy, localization, docs, sweep

**Files:**
- Modify: `lib/tijara_tides_web/components/game/queued_trade.ex` (help
  sentence), `priv/gettext/*.pot|po` (extract + Arabic), `docs/IMPLEMENTATION.md`,
  `docs/architecture.md` if the error/command list is documented there,
  `docs/ux-inventory.md` (regenerate), control sweep exclusions/handlers.

- [ ] `mix gettext.extract`; add Arabic for every new msgid;
  `python3 scripts/check-gettext-catalogues.py`.
- [ ] Update docs; `python3 scripts/gen-ux-inventory.py` (or the matching
  `scripts/gen-*.py`); `python3 scripts/check-generated.py`.
- [ ] `python3 scripts/test-game-db.py --control-sweep` passes, pressing the
  dialog and panel controls.
- [ ] `scripts/check-local.sh --full`; count warnings (must be zero). Commit.
