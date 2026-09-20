# Factory inventory advertised as purchasable cargo

## Observed failure

Production commit `2af5ff67799978d74b8d4c43db8372aac754a8b1` raised
`ArgumentError: Market cannot supply the requested cargo quantity or price`
during a player command at 2026-09-20 13:12:05 UTC. Readiness returned 503 from
13:12:07; Render sent SIGTERM at 13:12:57, and readiness recovered at 13:13:37.
The user reproduced the failure, with another command exception at 13:16:35.

A read-only production query found 480 lots of aluminium scrap at Tangier with
`feedstock=true` and `seller=false`, and Naval Gazers 2 docked there. Logs did not
include command arguments, so attribution to that particular click is inferred.
A local purchase of Tangier aluminium scrap reproduced the same supply stack
on the deployed commit without accessing production storage.

## Cause and blast radius

`PortCargoMarket.quote/2` advertised physical stock without checking seller
eligibility. Manufacturing inputs are legitimately stored by non-seller markets,
so positive inventory is not proof of executable supply. UI purchase limits
trusted the quote. `TradeSettlement.buy/11` checked quantity, price, capacity and
funds but omitted the seller check; the lower-level supply invariant then raised.

`OperationBoundary.call/6` treated every exception as a reason to pause the whole
owner. The failure occurred in pure planning, before command persistence, so the
candidate could safely have been discarded without stopping the world. Restart
restored availability but could not remove the deterministic trigger.

## Why green tests missed it

The deployed commit's [CI run](https://github.com/adsouza/tijara-tides/actions/runs/35479272153)
passed all 658 tests, including the disposable PostgreSQL suite, on both runtime
versions. Line coverage was 93.43% on Elixir 1.20.2 and 93.52% on Elixir 1.19.3.

- `port_cargo_market_aggregate_test.exs` tested supplier release using
  `seller=true`; its ordinary consumer fixture had zero stock. It did not combine
  a non-seller's positive feedstock inventory with a public quote or manual buy.
- `manufacturing_test.exs` tested input inventory, replenishment and consumption,
  but not whether factory inputs were erroneously exposed as executable supply.
- Trade/UI fixtures exercised trading at ordinary suppliers or supplied synthetic
  quote maps. There was no catalogue-wide invariant connecting advertised supply
  to the market's ability to release it.
- `operation_boundary_test.exs` explicitly asserted that any internal exception
  paused gameplay. In `game_server_failures_test.exs`, the fixture named
  `DomainException` actually raised from the persistence adapter's `query!/2`.
  It therefore did not test an exception from pure command planning at all.

Line execution coverage could not detect the missing combination of state and
behavior, and the old failure-policy assertions reinforced the excessive blast
radius.

## Changes and regression coverage

Quotes now expose supply only from sellers and demand/budget only from buyers.
Physical inventory and manufacturing prices remain intact. Settlement separately
rejects trades on the wrong market side with ordinary domain errors.

Only pure player-command planning catches unexpected exceptions, records redacted
diagnostics, and returns `:command_failed`. It discards the candidate without
writing a command receipt. Lot-ID exhaustion keeps its existing retry behavior;
receipt reads, sequence allocation, commit preparation, persistence, acceptance,
and lifecycle/progression failures retain their existing halt policy.

Contained rejections use `:command_failed` in replies and operation-log reasons,
with player copy saying the game is still running. `:internal_error` remains
reserved for the existing pause response and its operator-contact message.
This distinction prevents a rejected command from being presented as an outage.

New tests cover the real catalogue's quote/supply contract, market-role
combinations, Tangier UI limits and direct commands, a different injected supply
invariant violation, recovery after conflict reload, and exceptions in storage
and after commit. A PostgreSQL-backed owner test verifies unchanged game state,
projection, durable revision and receipts, continued readiness/activity, and a
successful subsequent command without a restart.

## Local validation

`mix precommit` passed formatting, warnings-as-errors compilation, gettext checks,
and 604 tests (62 database tests excluded). The full disposable PostgreSQL run,
`python3 scripts/test-game-db.py --cover`, passed all 666 tests with 93.51% line
coverage. During validation, an existing rerouting UI test hit its implicit 100ms
async-refresh deadline; that database-backed wait now explicitly allows five
seconds. Its behavior assertions are unchanged, and the final full run passed.

After separating the failure reasons, the full PostgreSQL suite passed all 668
tests, including English/Arabic message regressions and the operation-log reason
check. Gettext extraction was run without merging; the runtime translation guard
passed with all five dynamic msgids preserved.
