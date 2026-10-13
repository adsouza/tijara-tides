# Queued trade margin: a price allowance for trades that must wait

Lets a player give a manual port trade that will be queued a small price
allowance, so ordinary market movement during the wait does not leave the order
unfilled. Written 2026-10-12.

## Intent

A manual buy or sell sends the exact quote on screen as its limit. When the
ship is loading, unloading or waiting for a berth, the trade is queued and
retried each tick, and `TradeSettlement` refuses it while the ask is above (or
the bid below) that limit. The ask moves one percent of the reference price per
25 lots of stock, and clustered ports reprice on every trade in the cluster, so
a queued trade very often sits on "Waiting for the limit price" for a difference
of a few cents. Players see this as their order being held for a smidge more
than they offered.

Success means that a player whose trade is about to be queued is offered a
margin with a short explanation, can accept it once or for all future queued
trades on that side, can later change or withdraw that default from the trade
panel, and that a queued trade with margin `m` fills whenever the price has
moved by no more than `m`.

Decisions taken during design:

| Question | Decision |
|---|---|
| Who decides that a trade will queue | The server; the UI never predicts it |
| Sides | Buys and sells, each with its own saved default |
| Margin range | 0–10% (0–1,000 basis points); slider steps of 0.5%, default 2% |
| Where a default lives | On the account, like the language choice |
| Where the default is changed | A compact control under the port trade controls |
| Trades that execute immediately | Use the exact quoted limit; the margin is ignored |

Out of scope: margins on route and ship instructions (their limit is already an
editable field), on exchange orders, warehouse transfers and auctions, and any
change to the price a trade settles at.

## Behaviour

### Settlement is unchanged

The margin widens only the limit stored on the queued trade. A buy still pays
the ask at execution and a sell still receives the bid at execution; the margin
is the most the player allows the price to move against them, not a surcharge.

### Manual limit range

A manual trade's `limit` is admitted only in 0..1,000,000,000,000 cents, the
player price ceiling that exchange orders, route limits, auction bids and
markdown floors already use. Today any non-negative bigint is accepted; no UI
sends a larger value, since quotes derive from catalogue reference prices. New
code reads the ceiling from one constant, `TijaraTides.Domain.Prices.max_cents/0`;
the existing literals elsewhere are left for a separate cleanup. A limit above
it returns `{:error, :invalid_trade}` from submission. Pending trades already
stored with a larger limit are not resubmitted; the retry in
`BerthAllocation.advance/2` executes them unchanged.

### The margin limit

`TijaraTides.Domain.Trade.queued_limit(side, limit, margin_bps)` is the one
definition, used by the command and, through a use-case query, by the dialog's
worst-case figures. It uses exact integer arithmetic only:

- Buy: `min(Prices.max_cents(), div(limit * (10_000 + margin_bps) + 9_999,
  10_000))`. Because an admitted `limit` is at most the ceiling, the result is
  never below `limit` and always fits the `pending_limit bigint` column.
- Sell: `div(limit * (10_000 - margin_bps), 10_000)`, which stays at or above
  zero for every admitted margin.

Rounding favours filling: the buy ceiling rounds up and the sell floor rounds
down.

### Command contract

Admission (`CommandPayload`):

- `buy` and `sell` admit two more optional fields, `margin_bps` and
  `save_margin`.
- A new action, `queue_margin`, admits `side` and `margin_bps`.

Dispatch (`Commands`) builds the `Trade` with two new fields, `margin_bps`
(default `nil`) and `save_margin` (default `false`), and keeps "absent" distinct
from "malformed":

- `margin_bps` absent means no explicit margin. Present, it must be an integer
  in 0..1,000.
- `save_margin` absent means `false`. Present, it must be a boolean, and `true`
  requires `margin_bps`.
- `destination` is kept only for buys, where it must be a catalogue port id.
  A sell's destination is discarded rather than copied into
  `pending_destination`; today a sell copies an unvalidated client string into
  that text column, and a value containing U+0000 would fail at commit and
  pause the world.

Admission errors keep their existing precedence: an integer beyond signed
bigint is still refused by `CommandPayload` as `:command_value_invalid`. An
admitted but malformed value returns `{:error, :invalid_trade}`
(`:invalid_queue_margin` for the `queue_margin` command) before any state
changes.

The ordinary `trade` form handler is unchanged and never adds either field, so
existing trade payloads keep their fingerprints and replay their receipts. Only
the dialog's confirm handler adds them: `margin_bps` parsed from the slider
with the existing integer parser, and `save_margin => true` only when the box is
ticked; an unticked box leaves the field absent. The `false` default is applied
when dispatch builds the `Trade`, never in the transport payload.

### Command flow

`BerthAllocation.submit` validates the trade exactly as today, against the exact
quoted limit. At the two points where it would queue the trade (ship loading or
unloading, and `:berth_busy`), it resolves the margin:

1. `trade.margin_bps`, if present;
2. otherwise the account's saved default for this side, if set;
3. otherwise it refuses with `{:error, :queue_margin_required}`, changing
   nothing.

With a margin it stores `Trade.queued_limit/3` as `pending_limit` and queues as
today. If `save_margin` is true, `AccountWorld` writes the default in the same
commit; the command's single commit means a persistence failure leaves neither
the queued trade nor the default. A trade that executes immediately ignores
`margin_bps`; `save_margin` still stores the default, since the player chose
it.

Because the refusal happens only after validation, the dialog appears only for a
trade that would otherwise have been queued.

### Saved defaults

`Account` gains `queue_margin_buy_bps` and `queue_margin_sell_bps`, each `nil`
(ask me) or an integer 0..1,000. The `queue_margin` command, owned by
`AccountWorld` as `locale` is, takes `side` (`"buy"` or `"sell"`) and
`margin_bps` (an integer 0..1,000, or `nil` to return to asking). The read model
exposes both values in the account's private view.

### Retained command and resubmission

On `:queue_margin_required` the LiveView assigns `queue_margin_prompt`: the exact
normalized command it just sent, including its request id, plus the dialog's
current slider and checkbox values. It shows the dialog instead of an error
flash.

"Queue trade" adds only the parsed `margin_bps` and `save_margin` to that
retained command and sends it through `run/2` directly. It does not rerun the
`trade` handler, so a ship or destination selected while the dialog is open
cannot change the trade, and already-parsed integers are not parsed again.

A refused command commits no receipt, so reusing the request id is valid.

- Success closes the dialog and issues a fresh request id, as `run/2` already
  does.
- An error closes the dialog, shows the error flash and refreshes the view, as
  `run/2` does for every command. Errors whose durable outcome is uncertain
  (a commit followed by a failure, or a lost connection) are handled exactly as
  for any other command today: nothing is resubmitted automatically, and the
  refreshed view shows whether the trade was queued.
- "Cancel", Escape and click-away discard the assign without sending anything.
- LiveView handles events in order, so a second confirm event arrives after the
  assign is gone and is ignored.
- The prompt is not retained across a reconnect; a remount starts with no
  dialog and a fresh request id, as for every other form.

### Dialog

The dialog contents:

- Title: "Allow a price margin?"
- Note: "This ship can't trade right now, so the order will wait in the queue.
  Prices often move a little meanwhile, and an order at exactly today's price
  would then sit unfilled. A margin lets it go through; you still pay (or
  receive) the market price when it executes."
- A slider from 0% to 10% in 0.5% steps, starting at 2%, with the percentage
  shown beside it.
- A live worst case under the slider, from `GameQueries.queued_limit/3`, which
  delegates to `Trade.queued_limit/3`: for a buy, "Up to $X per lot, $Y in total
  before handling"; for a sell, "At least $X per lot, $Y in total before
  handling".
- A checkbox: "Use this margin for all future queued buys" (or "sells"),
  unchecked by default.
- Buttons "Queue trade" (resubmits with `margin_bps` and `save_margin`) and
  "Cancel" (closes without trading). Escape cancels and focus stays inside the
  dialog while it is open.

Any other result of the resubmission is shown as today: "Trade queued", "Done",
or the error flash. The dialog's slider and checkbox are a client form within
the LiveView; the worst-case figures are rendered by the server so the domain
function remains the only arithmetic.

### Trade panel control

Beneath the port trade controls, one compact line: "Queued-trade margin: buys
Ask me · sells 2.0%". Each side has an editor with the same 0–10% slider and a
Save button (`queue-margin-save`, sending the parsed integer), plus a separate
"Ask me each time" button (`queue-margin-reset`, `phx-value-side`) whose handler
sends `margin_bps => nil` explicitly rather than parsing a form value. Both send
the `queue_margin` command for that side only.

### Queued trade card

The existing card already shows the stored limit ("Buy 120 lots of Coffee at no
more than $X per lot"), so it shows the widened limit without change. Its help
text gains one sentence: "A margin, if allowed, is already included in this
limit."

## Storage

Migration `add_queue_trade_margins` adds to `game_accounts`:

```sql
queue_margin_buy_bps integer CHECK (queue_margin_buy_bps BETWEEN 0 AND 1000),
queue_margin_sell_bps integer CHECK (queue_margin_sell_bps BETWEEN 0 AND 1000)
```

Both columns are nullable with no default, so existing accounts are asked. The
account row codec (`Account.Rows`) adds both to its exact field list, so every
encoded row carries them, `nil` included. `GameRows` maps both columns and adds
both to `@required["accounts"]`, so a row that omits either key is refused
before SQL rather than binding `nil` and silently clearing a saved default. No
new table is added, so table ownership is unchanged.

## Localization

All new strings go through Gettext. Run `mix gettext.extract`, add the Arabic
translations, and check with `scripts/check-gettext-catalogues.py`. Percentages
and money use the existing formatting helpers so Arabic renders correctly.

## Documentation

Update the manual-trade and berth-queue sections of `docs/IMPLEMENTATION.md`,
the queued-trade help text, and `docs/database.md` for the new columns.
Regenerate `docs/ux-inventory.md` with its script.

## Testing

Domain:

- `Trade.queued_limit/3` for both sides at 0, 50, 200 and 1,000 basis points,
  including rounding at odd cent values and the clamp at the price ceiling.
- `submit` with the ship handling and with a busy berth: no margin and no
  default refuses with `:queue_margin_required` and leaves state unchanged; an
  explicit margin stores the widened `pending_limit`; a saved default applies
  without a command margin; an explicit margin overrides the default;
  `save_margin` stores the default in the same commit; an immediate execution
  ignores the margin.
- Invalid `margin_bps` (−1, 1,001, a float, a string) and invalid
  `save_margin`, plus `save_margin` without `margin_bps`, are refused through
  `GameCommands.run` as well as the domain, with no commit; a `margin_bps`
  beyond signed bigint is refused at admission as `:command_value_invalid`.
- A manual limit of exactly 1,000,000,000,000 is admitted and one cent more is
  refused; a ceiling limit with a 10% buy margin stores the ceiling.
- A queued sell stores no `pending_destination`; a buy whose destination is not
  a catalogue port, or contains U+0000 or invalid UTF-8, or is not a string, is
  refused with no commit.
- `queue_margin` sets, changes and clears each side independently, and refuses
  out-of-range values and unknown sides.

Contract: a queued buy at margin `m` fills when the ask rises to exactly
`queued_limit` and stays queued at one cent more; the sell equivalent for the
bid. The dialog's worst-case figure equals the stored `pending_limit`.

Database: the migration round-trips both columns, including `nil`; an account
row missing either key is refused before SQL; a value outside 0..1,000 cannot
reach a commit; a sell sent with a U+0000 destination and a margin queues
without pausing the world; a failed commit of a trade with `save_margin` leaves
neither the queued trade nor the default.

LiveView: a queued trade without a default opens the dialog and queuing from it
stores the widened limit; Cancel queues nothing; changing the selected ship or
destination while the dialog is open does not change the confirmed trade; a
second confirm event is ignored; ticking the checkbox saves the default and the
next queued trade on that side opens no dialog while the other side still does;
the trade panel control changes each default, and its reset button clears one
side while the other keeps its value; a trade form submission carries neither
new field, so its payload matches the pre-feature payload exactly; the control
sweep (`--control-sweep`) presses the new controls.

Existing tests: every test that queues a manual trade today (berth, game,
offers, persistence and control-sweep tests) would now receive
`:queue_margin_required`. Each passes an explicit `margin_bps`, chosen so its
existing assertions still hold; the control sweep confirms the dialog. One test
keeps the old path's limit behaviour by confirming with a 0% margin.

Each new guard is broken once to confirm a test fails.
