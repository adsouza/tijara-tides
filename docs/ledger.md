# Financial ledger and cargo identity

The first production deployment includes accounting and lot-identity foundations
without introducing warehouses, auctions, loans, or player industry. Current
company finances are backed by immutable journals; active cargo is backed by
permanent lot records.

## Accounting convention

Every journal belongs to one company and contains at least two nonzero entries.
Positive cents are debits and negative cents are credits; the entries sum to
zero. Transactions record event kind, world time, world revision, optional ship
and cargo context, and the request ID when created by a command. These are
company books: computer-controlled counterparties are represented by revenue,
expense, asset, or capital accounts, not player-company balances.

| Event | Debits | Credits |
|---|---|---|
| Starter grant | Available cash and fleet book value | Capital |
| Cargo purchase | Inventory at acquisition cost; handling and cleaning expenses | Available cash |
| Cargo sale | Cash received; cost of goods sold; handling expense; repayment of payables | Sales revenue and inventory at acquisition cost |
| Departure | Reserved cash and canal expense | Available cash |
| Fuel consumption | Fuel expense | Reserved cash |
| Crew costs | Crew expense | Available cash for paid costs; payables for arrears |
| Spoilage | Spoilage expense | Inventory at acquisition cost |

Fuel reservations move money between two asset accounts; they are not expenses.
Company `cash_cents` includes both available and reserved cash. Paying existing
arrears reduces cash and payables without charging the expense a second time.
Inventory stays an asset until sold or spoiled. Fleet book value is stored per
ship and initially equals its class purchase price; depreciation remains future
work. Sale handling is expensed separately even though the UI reports net
proceeds.

## Posting and recovery

Domain rules build balanced pending events using integer cents. Persistence
writes new lots, holdings, game records, journal transactions, and command
receipts inside one transaction under the world-owner lock. A failed write rolls
all of them back, including the lot counter. Retrying a committed request returns
its receipt and cannot post another journal.

A journal starts unsealed inside its transaction. Posting checks the line count
and zero sum, updates account totals, and seals it. A deferred database check
prevents committing an unsealed header. Database triggers reject edits/deletions
to journal history and additions to sealed journals. Corrections are new
compensating entries. Ledger totals cannot be edited directly; the posting
trigger maintains them.

After posting, persistence reconciles available plus reserved cash, reservations,
unpaid costs, profit, cargo book value, and fleet book value against current game
records. It checks materialized totals, so ordinary ticks do not rescan all past
entries. Startup separately audits those totals against journal history before
claiming readiness. Pending domain events are cleared after successful commit;
the world process does not retain the full financial history.

Existing companies receive opening entries at migration. Opening profit preserves
the existing trading result; the remaining net assets are balanced against
opening capital. These entries document the starting position and must not be
misrepresented as historical purchases or revenue. Queries for post-migration
performance must distinguish `opening_balance` from subsequent activity.

## Cargo identity and splits

`game_cargo_lots` records the immutable identity, cargo type, original quantity,
expiry, creation time, and optional parent. `game_cargo_holdings` records the
current ship or market, FIFO position, and acquisition cost where owned. A single
primary key prevents simultaneous holdings for one lot.

A full transfer preserves its ID. A partial transfer or sale consumes the parent
holding and creates two new IDs: one for the taken portion and one for the
remainder. Both reference the parent and retain its cargo type and expiry; their
quantities sum to its original quantity. FIFO ordering and manifest aggregation
never replace these identities. Sold or spoiled lots remain in the registry even
though their active holding is gone. Non-perishable simulated supply is currently
an aggregate until purchase, when it creates a new root lot; perishable market
stock already consists of lots.

These records support later warehouse locations and reservation/auction
references. New location types will require an explicit migration. They do not
yet constitute a complete movement-history system or an auction implementation.

## Inspection

With normal read-only database access, a company's journals can be inspected
without starting the game owner:

```sql
SELECT t.id, t.kind, t.clock_ms, t.request_id,
       e.account_code, e.amount_cents
FROM game_journal_transactions t
JOIN game_journal_entries e ON e.transaction_id = t.id
WHERE t.world_id = 'ocean' AND t.company_id = '<company-id>'
ORDER BY t.id, e.position;
```

Stop the game owner before maintenance edits and restart it afterward. Financial
maintenance must update game summaries and post balanced adjustments atomically;
editing balances alone is rejected by reconciliation. Backups retain the actual
pre-migration history available to us, not a reconstruction.
