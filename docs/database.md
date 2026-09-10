# First playable milestone

The current playtest covers invitation-based accounts, one lasting company per
account, loan-funded ship purchases, depreciated shipyard buybacks, manual port
trading, timed voyages, next-port cargo instructions, repeating routes and optional
automatic departure. Company finance includes loans, recasts, bankruptcy, escalating credit
rates, account suspension and sponsor guarantees. Verified email linking and
sign-in, email invitations, and quarterly/yearly financial reports and
leaderboards are also implemented. The approved design remains
authoritative; the provisional tuning and deferred systems below describe the
current implementation.

Auctions, standing exchange orders, warehouses, escalating age-based maintenance
and player industry remain deferred. Next-port instructions are implemented;
they execute ship-specific buy/sell actions on arrival rather than placing
standing orders on a shared exchange.

See [architecture and domain boundaries](architecture.md) for command workflows,
query projections, consistency and module responsibilities.

## Data and authority

- Domain operations receive explicit time, identifiers, and catalogue data. They
  perform no I/O. Money, weight, volume, quantities, and simulation time use
  integers; trade limits and ship capacity are checked before mutation.
- PostgreSQL holds accounts, hashed device credentials and invitations, a world
  ownership epoch and simulation clock, typed relational game records, and
  command receipts. Cargo has permanent lot IDs with separate holding rows; foreign
  keys and checks protect references and numeric invariants. A transaction locks the world row, verifies its owner epoch, checks
  the authenticated account and request identity, writes only changed columns and batch rows,
  and records the result. Publish and acknowledge only after commit.
- A fresh world process claims a new epoch. A superseded process becomes
  unavailable instead of reclaiming ownership. No game assets are created in
  the database-free lobby. Container startup applies pending migrations before
  starting the game; launch invitations still require explicit operator seeding.
  Direct `mix phx.server` requires prior migration. See [database operations](database.md).
- Startup restores the last committed simulation clock without wall-clock
  catch-up. An authenticated connection starts progression; it continues while
  the server stays awake, including after disconnect. Static catalogue and map
  definitions are versioned source assets, not repeated database writes.
- Public views contain company names, ships, positions, and routes. Each port
  shows its present ships grouped by status, company or kind, with expandable ship
  lists; ships at sea do not count toward either endpoint. Only an
  authenticated owner receives balances, cargo batches, acquisition costs,
  private notifications, and command results. PubSub announces revisions, not
  private state. Every command revalidates the device session on the server.

## Playtest scope and tuning

The first market screen offers manual immediate trades against finite simulated
supply and demand for order-book cargo. Luxury and contract goods stay visible
in the catalogue but cannot bypass their future auction mechanisms. Quantities,
reference prices, production rates, ship prices, and travel scaling are explicit
provisional tuning values. Voyages currently run at 600× sailing speed with a
six-second minimum (10× faster than the initial playtest). Existing voyages are
retimed on their next tick, preserving progress and fuel already spent.
New perishable production has correspondingly shorter shelf lives: fruit 7h 12m,
seafood 3h 36m, and meat 4h 48m of active-world time. Existing lots retain their
stored expiry timestamps; buying or splitting a lot does not reset its age. New
companies start with no cash or ships; players borrow up to $250,000 and buy ships
at any port. Existing companies retain their assets.

Hull depreciation uses a provisional 28-active-world-day useful life: one game
year at the unchanged four-week reporting calendar, not twenty game years.
Straight-line depreciation reduces build value to a 20% residual; shipyard
buybacks pay 90% of current book value. The shorter life lets playtests exercise
replacement sooner. It is separate tuning from the 600× voyage speed, not a
rescaling of all world timers. Existing hulls start aging from the deployment
clock at their then-current book value; no retrospective depreciation is charged.

Age-based maintenance escalation is deliberately deferred. Current crew upkeep
is age-independent, with reduced upkeep when docked or waiting and higher upkeep
while sailing. A hull at residual value can therefore operate indefinitely at
the same crew rate. Buyback provides voluntary divestment, but the economic
pressure to retire old hulls and sustain the replacement cash sink is incomplete.
Before evaluating long-term fleet turnover or money-supply balance, implement
and tune the published post-useful-life maintenance curve in DESIGN.md §10,
including the cost crossover against a replacement hull and its UI disclosure.

Manual purchases require a destination with a valid voyage. After paying for
cargo, handling, and any tanker cleaning, available cash must cover fuel for the
loaded ship, canal fees, and estimated upkeep for the whole fleet through loading
and arrival. Estimates assume departure immediately after loading and no other
new fleet activity. This check does not earmark funds: subsequent spending or
waiting can change affordability, and departure still rechecks funding. It does
not provide recovery for companies already stranded without cash.

Port trade controls share a bounded lot quantity between a slider and number
field. Purchases default to the largest affordable load after capacity, stock,
handling, cleaning, and voyage-funding checks. Sales default to the smaller of
cargo aboard, demand, and the buyer's funded quantity. Both obey the 10,000-lot
command limit. Zero feasible lots disables both controls and the trade button.
Explicit choices survive live updates within the new bounds; changing ship or
destination and completing handling restores maximum defaults. The slider sits
above the numeric field and action button, with the purchase total below.

The current port's Buy view includes the chosen destination's current bid and
demand when an executable buyer exists there. The per-lot spread compares that
bid with the local ask before handling and voyage costs; it is not guaranteed
profit or a reservation of destination demand. These quotes update live.

On startup, an empty docked ship is preferred, with its current port selected.
Later updates preserve the player's ship selection. Fleet status filtering does
not silently change that selection. The Cargo demand table adds sea-route
distance in nautical miles from the selected docked ship, after price and demand
as the third default sort key. Unknown distances remain last.

Inspecting another port with a docked ship opens a destination comparison using
compatible stock at the ship's current port. Each candidate load is capped by
source supply, destination demand, and remaining weight and volume capacity.
Estimated profit deducts purchase and sale handling, tanker cleaning, loaded
fuel, canal fees, fleet upkeep through arrival, and a conservative unloading
upkeep allowance. It assumes current prices and immediate dispatch; available
cash and spoilage are not modeled in this planning estimate. Goods without an
executable destination buyer remain visible with no profit estimate.

Sea routes are precomputed from a maritime network and displayed on an
Equal Earth map. The world overview groups the Pearl River Delta, Northern
Frangistan, and Strait of Hormuz ports into numbered markers. Selecting a group
zooms to its labeled harbors with more detailed 1:10m coastlines and provides a
port list; World view restores the overview with lightweight 1:110m coastlines.
Northern Frangistan includes Antwerp, Hamburg, and Rotterdam. The map’s Ship
filters dropdown offers ship-class checkboxes, all enabled initially. Authenticated
players can uncheck “Show other companies’ ships” (enabled initially) to see only
their own fleet. Filters affect sailing markers and their routes, preserve port
markers, and survive world updates and regional navigation. Routing is for game
visualization, not real navigation. Voyage
estimates show duration, reserved fuel, canal fees, and crew costs. Port handling
costs vary with the port cost tier; load/unload operations take time.
Stored cargo retains its cost and freshness. Perishable trades disclose estimated
time to first expiry after handling for the entered quantity. Voyage estimates
show time to first expiry at arrival and after unloading all current cargo, and
update while underway. Public ship inspection shows company, class, and status
without exposing cargo. Selecting a port updates its market view. World suspension
pauses simulation timers; wall-clock session and magic-link expiry still apply.

Raw-resource producers replenish finite stock; manufactured goods have a finite
initial allocation until input-consuming production is implemented. Re-export
merchants remain unavailable until their warehouse-backed inventory exists.
Major and minor trade roles currently share the same provisional rate; role-weighted
production remains part of the full economy. Consumer demand and spending budgets
replenish and are capped. Supply and demand recover one lot every 150 seconds
of active world time (0.4 lots per minute); buyer budgets recover one lot’s
reference value on the same interval. Partial intervals carry across ticks. This is a manual
NPC market adapter, not the eventual central limit order book. Berth capacity
and queues, warehouses, standing exchange orders, and annual
invitation allocations remain deferred. Next-port cargo instructions and optional
automatic departure are available. Operating shortfalls accumulate as unpaid
bills and participate in the implemented loan settlement and bankruptcy rules.

Launch invitations grant three outgoing invitations; ordinary invitees initially
have no outgoing quota. Unused invitations expire after three active-world days
and restore their inviter's quota. Device sessions expire after one wall-clock
year. Before redemption, GET /play delivers a private random device credential
in the signed, HTTP-only cookie. A lost redemption response can be retried using
that same credential, including after server restart. Another device holding
only the invitation cannot recover the account; revoked or expired credentials
cannot be revived. POST without the pre-issued cookie consumes nothing.
Verified email linking, email delivery, and email sign-in are implemented. Players
with a linked email can regain access on another device; accounts without a linked
email still depend on their existing device session. Desktop users can redeem an
emailed token inside the app. Google sign-in remains deferred.

## Verification gates

1. Pure rules: conservation, integer arithmetic, private projections, capacity,
   stale quotes, costs, freshness, and zero-asset onboarding and ship purchases.
2. Disposable PostgreSQL: concurrent invitation redemption and command replay,
   transaction rollback, ownership fencing, account/session isolation, and
   restart recovery. Never use shared Neon for tests.
3. Browser flow: redeem an invitation, establish a persistent session, choose a
   company, borrow, buy ships and cargo, sail, arrive, sell, and reconnect.
4. Full precommit, generator consistency, assets, and release smoke checks.

## Following milestones

Standing order matching; berth queues; warehouse leases
and reservations; auctions and procurement contracts; age-based maintenance.
Player-owned industry stays a later expansion under section 14.

Markets by cargo compares applicable ports in two tables: Supply on the left
and Demand on the right, stacking on narrow screens. Each shows quantity and its
relevant price, with independent sorting and clickable ports. Supply defaults to
ascending price then descending supply; demand defaults to descending price then
descending demand, then ascending sea-route distance on the demand side. Cargo
selection and sorting persist through live updates. These tables omit ports
without executable supply or demand; deferred trading systems do not contribute
executable quotes.

## Accounting and lot foundations

Financial events use an append-only double-entry ledger. Historical capital grants,
purchases, sales and cost of goods, handling, cleaning, canal fees, fuel
reservations/consumption, crew costs/arrears, and spoilage post atomically with
state changes and receipts. Company summaries reconcile with ledger balances;
startup also verifies those balances against historical entries. Existing
playtest companies receive explicit opening entries rather than fabricated
history. Loan and bankruptcy accounting is implemented; auctions and a raw
ledger-history UI remain deferred.

Cargo-lot IDs survive transfers and FIFO reordering. Partial purchases and sales
split the source into child lots whose immutable parent link preserves lineage.
Consumed and spoiled identities remain in the database. The counter and all
new identities participate in the same transaction as holdings and accounting.

### Playable company finance

The account overlay supports bank borrowing, repayment schedules, full early
repayment, partial repayment through recasting, and confirmed voluntary bankruptcy. Domain finance settles oldest-due
installments and operating bills without using reserved voyage funds. One
24-active-hour grace period leads to forced bankruptcy; suspension pauses it.
Bankruptcy history, a 20-active-minute restart cooldown and reduced credit
limits survive database reloads. Closed companies retain their assets for
future receivership auctions, which are not implemented in this milestone.

## Verified email identities

Players can link an email from the account menu. Email verification appears above
Invitations; Invitations stays hidden until an email is verified. Once linked,
the verified address appears on the left of the popup header beside Close; the
verification form and delivery status are hidden. The underlying identity workflow supports replacement and preserves
an existing email until the new address is confirmed. Email sign-in on the web
creates a new device session for the same account. Google sign-in remains deferred.
Email invitation controls sit on the left, with available invitations above the
email field. The shareable-code button sits to the right, separated by "or", with
bottom edges aligned. The controls wrap on narrow screens. When no invitations
remain, the controls and explanatory text are hidden; the zero count and any
already-generated code remain visible.
An email invitation consumes the sponsor's normal quota and atomically creates an
account with the verified recipient email when redeemed. Shareable invitations
continue to create accounts without an email. Sponsors see delivery status and
acceptance, never the recipient's credential; accounts are not implicitly merged.

Magic links for linking and sign-in expire after 15 wall-clock minutes. Invitation
links follow the existing three-day active-world expiry and quota restoration.
GET requests prepare a confirmation screen; a CSRF-protected POST consumes the
single-use credential. Lost-response retries on the same device are idempotent.
Requests are limited per requester and email. Credentials are stored as hashes;
a durable outbox retries delivery with exponential backoff, stopping after eight
failures. Delivery is at least once, so a rare retry may resend the same link.

The account menu hides Sponsor guarantees unless there is an active guarantee,
an outstanding sponsor pledge, or an invitee awaiting sponsorship. Loan-rate
and required-guarantor guidance remains in Loans and repayments.

Loan-rate, installment, interest-accrual, bankruptcy-rate and early-repayment
explanations share a collapsed Loan terms disclosure. Its open state survives
live updates; balances and actionable loan warnings remain visible.

Invitation expiry uses the largest whole unit rounded down: approximate days or
hours (for example, ~2 days or ~1 hour), then minutes or seconds below an hour.

Declare bankruptcy is shown only when the company is eligible to declare; no
disabled button or ineligibility explanation is displayed.

Ship details show the depreciation explanation beside book value. The sale
button and buyback percentage sit inside a collapsed Shipyard offer disclosure,
which is hidden while sailing. Its expanded state survives live updates for the
selected ship.

## Company results and leaderboards

The Results & leaderboards panel is available to spectators and players. It
provides quarter/year and profit/ROI selectors, ranked completed periods and
unranked provisional results. Company owners also see sales revenue, cargo sold
at cost, operating costs (including spoilage and asset-disposal losses),
depreciation, net profit and average capital employed. Public results never expose
cargo holdings or cost breakdowns. Bankruptcy history remains attached to accounts;
former companies retain their own reports and restart companies begin afresh.

Periods are anchored to active-world clock zero: quarters last seven days and
years twenty-eight. Journal events at an exact boundary belong to the new period.
Capital is integrated with integer cent-milliseconds between committed asset
changes; integration splits at every period boundary. Borrowing adds assets but
not profit; reserved cash and pledged guarantees remain capital. ROI is net
profit divided by time-weighted assets, never shareholder equity. Zero capital,
partial periods and companies bankrupt before period end are unranked. Quarterly
profit and ROI reports offer the current quarter and latest three completed
quarters through a dropdown. Yearly history remains available.

Migration `20260910000000_add_financial_reports.exs` adds typed reporting-account
and period-summary tables. Summaries update in the same transaction as domain
entities, journal entries and command receipts. Existing companies begin tracking
at the first startup with this feature; earlier results are not reconstructed or
ranked. Their current period is provisional unless tracking begins exactly at its
boundary. Deploy and test on a disposable database before applying locally; the
normal production startup migration mechanism applies this schema on deployment.

The panel fetches one selected period on opening or selection and supports explicit
refresh. Each ranked, provisional and owner list is paged at 10 companies. Owner history
has separate page controls from the leaderboard. The
application query layer owns ranking and retention policy; the component renders
its prepared results. Ordinary world ticks do not reload report history.

## Repeating routes

The Ships panel has a collapsed Repeating route editor, using the existing form,
button and disclosure styles. One ship can have one private route with two to
eight ordered stops and at most twenty cargo targets per stop. Adjacent stops
and the final/first pair must differ. The final stop returns to the first.
Running and paused routes remain editable. Cargo targets can be added, edited,
or removed; already-created visit orders retain their original terms, including
quantity mode. Changes apply when the relevant stage next creates orders.
Future stops can be added or removed while preserving the active stop identity.
The current and next stops are protected, as is appending a new next leg after
orders for the final stop have been created. Every active circuit stays valid. Removing a route preserves its cargo,
committed handling and current voyage while cancelling future route activity.
Existing single-visit instructions and onward plans must be cleared first;
route-managed ships cannot also receive independent next-port instructions.

Each stop sells up to its configured quantity from cargo actually aboard, then
finishes unloading before calculating purchase shortfalls. Load targets include
retained cargo; a fresh per-visit cap limits purchases including handling and
cleaning, without earmarking cash. Prices use the same limit semantics and
voyage-affordability checks as manual and single-visit trades. Partial fills retry
and never accumulate across circuits. Once sales finish, exhausted hold capacity
cancels the remaining loading shortfall with notification. Other unfilled targets
wait until filled or explicitly cancelled. Expiry and maximum-wait controls,
warehouse collection, linked exchange orders and advance purchase budgets remain
future extensions.

Automatic departure is off by default. With it disabled, the existing voyage
controls provide manual Sail. With it enabled, normal funding and handling guards
apply; blocked departures show their reason and retry. Pause stops new route
fills and automatic departures, while committed voyages and handling finish.
Resume retains the current visit's fills. Stop after this visit finishes its
orders and handling, then pauses before departure. A manual departure to another
port pauses the route; return to its selected stop before resuming. Start requires
the ship to be at, or sailing to, the first stop.

Migration `20260911000000_add_repeating_routes.exs` adds relational route, stop and
target tables. The current cursor, visit counter and execution phase commit with
cargo instructions, trades, ledger and command receipts. Only the current visit's
instruction rows are retained, keeping route execution bounded across circuits.
Restart restores progress without rematerializing filled orders or replaying
purchases. Route definitions and execution details are owner-only.

Route targets support fixed lots, **Buy maximum**, and **Sell all aboard**. Maximum
purchases use available hold, stock, free cash including voyage reserves, and the
purchase cap. Resource exhaustion completes the purchase for that visit; price
limits still wait. Sell-all quantities use cargo aboard at each visit and sell only what current
demand and buyer funds permit. Unsold cargo stays aboard and the route continues
after handling finishes; minimum-price limits still wait. Fixed targets remain available.

Migration `20260911000004` permits null route purchase caps. Null means no
additional spending cap; positive caps retain their existing enforcement.
