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

Luxury cargo auctions and standing warehouse-backed exchange orders are implemented.
Procurement and receivership auctions and player industry remain deferred.
Age-based maintenance is implemented alongside depreciation. Next-port instructions are implemented;
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
in the catalogue; luxury goods trade through scheduled warehouse-backed auctions,
while machinery awaits procurement auctions. Quantities,
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

Maintenance is a separate operating expense, with crew rates unchanged. Its
flat base rate costs 20% of the current replacement hull price over 28
active-world days. After useful life, its rate rises linearly: at 32.2 days
(15% beyond useful life) maintenance equals a new hull's base maintenance plus
straight-line depreciation. Older hulls therefore cost more to maintain than
that replacement benchmark. Charges integrate the curve over elapsed active
world time using integer cumulative differences, preserving cents across tick
sizes and reloads; rollout does not charge earlier intervals retroactively.
Unpaid maintenance follows existing operating-bill arrears rules and cannot
spend reserved voyage funds. The ship panel shows next-day and next-week costs
and the new-hull comparison; voyage and purchase-affordability estimates include
maintenance. Migration `20260923000000_add_ship_maintenance_account.exs` adds its
separate ledger account, included in operating expenses and profit reports.
These source-configured rates are provisional tuning, not a fleet-balance verdict.

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

The Ships destination selector opens a port-by-cargo opportunity matrix,
populated for a docked ship. Port names select the destination and close the
popup, switching to the current port's Buy view and scrolling to its market side
controls; that switch now follows a destination chosen for a sailing ship as
well. The choice is a persisted command on the hull rather than a
browser-session value, so it survives a reconnect and a second window, and
departing or rerouting clears it. Compatible cargo columns show green outbound
and red return symbols on one shared scale: circles price a fresh purchase here,
squares price cargo already aboard against the candidate port's demand. Symbol
size is proportional to positive ROI, with hollow symbols for zero or
unavailable ROI and black skulls for negative ROI. Purchase ROI is the current
bid minus ask and both handling fees, divided by ask plus purchase handling.
Aboard-cargo ROI uses the recorded lot costs a sale would consume, in that order
and including a partial fill of the final batch; cargo whose recorded cost is
zero reports its proceeds with no ROI rather than dividing by nothing. A good
stays in the matrix when the hold is the only reason to visit, with no local
stock required. Hover/focus exposes ROI, lots and aboard-cargo proceeds. These
are market comparisons, excluding cash, capacity, cleaning, voyage costs and
spoilage, rather than executable trade quotes. Ports sort by the sum of their
best ROI in each direction (missing directions contribute zero), then sea
distance. The popup supports Escape, explicit dismissal, keyboard focus
containment, Arabic labels and RTL layout.

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
Regional catchments use the catalogue's three clusters. Each good's shared
operating price responds to average eligible supplier stock and buyer demand,
within 80–120% of its fixed reference value. Local adjustments are capped at
±2 percentage points, with a one-point quote spread on either side. Every
executable regional NPC bid is additionally capped against every stocked
supplier's ask plus both ports' handling fees. This conservative transport
allowance includes no fuel/upkeep margin, preventing a positive instantaneous
NPC spread after handling. Quotes recompute from current inventories on every
read or fill; no cargo, demand, budget or receiving capacity is pooled, and
player limit prices and published auction commitments remain unchanged.
Major and minor trade roles currently share the same provisional rate;
role-weighted production remains part of the full economy. Consumer demand and
spending budgets replenish and are capped. Supply and demand recover one lot
every 150 seconds of active world time (0.4 lots per minute); buyer budgets
recover one lot’s reference value on the same interval. Partial intervals carry
across ticks. This is a manual NPC market adapter, not the eventual central
limit order book. Finite berths and queues, warehouse leases, transfers,
reservations, renewals and extensions are available. Annual invitation
allocations remain deferred. Warehouse-backed standing exchange orders are
available for standardized cargo. Next-port cargo instructions and optional
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

The completed decision groups in DESIGN.md describe agreed product rules, not
completed implementation. Luxury auctions, manual warehouse transfers and
repeating routes are already playable.

Regional catchment pricing and age-based maintenance have now been implemented,
with launch tuning described in this document. Remaining work includes:

- **Simulated economy:** input-consuming NPC manufacturing, warehouse-backed
  re-export merchants, differentiated production rates, and participation-scaled
  producer output and buyer budgets. Add economic activity weights, money-stock
  and source/sink monitoring, and price-level monitoring (§5).
- **Dormancy and estates:** durable owner-absence tracking and closure warnings,
  dormant liquidation without a bankruptcy count, receivership asset auctions,
  full warehouse liquidation stages, won-cargo storage grace and replacement
  leases, residual estate cleanup and terminal scrapping (§§5, 7, 11, 12).
- **Procurement:** machinery delivery auctions, supplier deposits, buyer funding
  and receiving-capacity commitments, delivery deadlines, settlement/default and
  system-fault protections (§7).
- **Perishable and unified markets:** freshness-graded order books, minimum
  freshness requirements, markdown schedules and presets, mixed-grade backing,
  freshness-aware reservation replacement, and direct ship trades against
  player order books (§§6–8).
- **Automation:** linked remote orders and their atomic handover at berth,
  earmarked advance purchase budgets, optional expiry and maximum-wait controls,
  and departure-funding allocation and accumulation policies (§8).
- **Ports and physical handling:** full ship-size, terminal and waterway limits,
  predictive queue estimates, automatic warehouse-transfer queuing, transfers
  between storage types, and utilization-triggered berth/storage growth with
  published construction lead times (§§4, 10, 11).
- **Accounts and disclosures:** earned annual invitations, Google identity
  linking, asset-triggered linking prompts, concrete suspicious-trade and
  invitation-subtree review mechanisms, and remaining required disclosures,
  including local-time estimates alongside actionable countdowns (§§2, 3, 7).

Numerical parameters remain tuning work; the systems above still need code and
verification. The sections below describe the current implementation and its
interim behavior. Player-owned mines and factories, land, construction, carriage
for hire and player-funded port infrastructure remain explicitly later
expansions under §14, separate from initial-game NPC manufacturing.

## Cross-port cargo markets

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
history. Loan, bankruptcy and luxury-auction accounting are implemented; a raw
ledger-history UI remains deferred.

Cargo-lot IDs survive transfers and FIFO reordering. Partial purchases and sales
split the source into child lots whose immutable parent link preserves lineage.
Consumed and spoiled identities remain in the database. The counter and all
new identities participate in the same transaction as holdings and accounting.

### Playable company finance

The account overlay supports bank borrowing, repayment schedules, full early
repayment, partial repayment through recasting, and confirmed voluntary bankruptcy. Domain finance settles oldest-due
installments and operating bills without using reserved voyage funds. One
24-active-hour grace period leads to forced bankruptcy; suspension pauses it.
Bankruptcy history, a 3-active-minute restart cooldown and reduced credit
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
Removing the current or next stop returns the route to draft and clears its
visit orders and onward plan; committed handling and voyages still finish.
Appending a new next leg after orders for the final stop have been created
remains protected. Every active circuit stays valid. Removing a route preserves its cargo,
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
linked exchange orders and advance purchase budgets remain future extensions.
Loading now takes compatible owned warehouse stock first, prioritizing stock
earmarked for the ship, before buying the shortfall. Transfers retain cost and
expiry and incur handling fees without consuming the market-purchase budget.

Starting or resuming a route in the UI enables automatic departure. Existing
routes are upgraded to automatic departure too. Normal funding and handling guards
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

Repeating-route purchase caps are optional. A blank cap persists as no cap, not
as zero or a large sentinel. Limit prices, available cash, voyage reserves, stock
and hold capacity still constrain every purchase. Existing caps remain in place
until the player clears them; existing visit orders keep their original cap.

Route cargo choices use ship-class compatibility rather than the current load.
A tanker can plan to sell refined fuel and then buy crude at the same stop.
Actual execution still forbids mixing liquid cargoes and applies cleaning costs;
unsold incompatible cargo must be cleared before the purchase can proceed.

## Localization foundation

English and Arabic UI and email catalogs, RTL layout, locale-aware currency
formatting and plural forms are implemented. Account language preferences persist
across web and embedded desktop sessions. New notifications store codes and
arguments; existing text notices remain readable. See [localization](localization.md)
for conventions and the remaining translation scope.

## Finite berth handling and arrival queues

Ports now have finite handling capacity: the provisional low/medium/high berth
tiers map to 2/4/6 berths, overridable with `berth_count` in the port catalogue.
Arrivals receive persisted FIFO tickets, ordered by arrival time and ship ID for
simultaneous arrivals. Loading and unloading occupy a berth; idle ships release
access and wait at anchorage at the existing reduced upkeep rate. No voyage fuel
is consumed while waiting. Existing idle ships do not monopolize berths.

A manual trade that is currently feasible but cannot obtain a berth becomes a
persisted, cancellable ship order. It reserves neither cash nor stock. The full
quantity, limit price, funds, capacity and onward voyage affordability are
rechecked before settlement; a changed market can leave it waiting. The Ships
panel shows the queued trade and its cancellation button. Port traffic shows
capacity, occupancy and queue positions without exposing anyone else's cargo.

Automatic cargo instructions share the same admission policy. Unviable queued
operations release their ticket at assignment, letting later eligible ships
proceed. Failed admission retries have a configurable five-minute active-world
cooldown (`berth_retry_ms`), and require viable conditions. Repeating routes
continue automatically once their handling and orders finish. Queued manual
orders prevent automatic or manual departure until filled or cancelled.

Size-specific terminal groups, adaptive port expansion, and predictive queue
wait estimates remain deferred; the current playable hull catalogue does not yet
model the design's full size classes. Manual ship–warehouse transfers are
implemented with berth access and handling time, as described below. Automatic
queuing of those transfers and transfers between storage types remain deferred.

In portrait mode, an accepted manual Buy or Sell switches from Ports to Ships
immediately, whether handling starts or the trade queues for a berth. Later queue
updates do not switch tabs again. Landscape layout and scroll positions are
unchanged by this automatic navigation.

Loading and unloading completion posts a private notice, except while the ship is
running a repeating route. With browser notification permission enabled from the
account popup, new completion notices also produce system notifications while
the app is connected. Reconnecting does not replay old notices. Browsers or
embedded clients without Notification API support show an unavailable control;
this is not a background push service for closed apps.

## Warehouse leasing and manual transfers

Ports now offer finite ordinary, refrigerated and liquid storage pools. Leases
use 100 m³ blocks, 1/3/7 active-world-day terms and a progressive quadratic
utilization quote. Empty leased space counts toward utilization. Initial pools
are 1,000/250/500 blocks respectively, with base daily rates of $1/$3/$2 per
block; these are provisional shared port defaults. Liquid leases are dedicated
to one cargo type; ordinary and refrigerated leases share space within their
storage type. The acceptance command checks the exact quoted total and capacity.

Rent is paid from free cash into a prepaid asset and amortized over the term.
Releasing unoccupied blocks refunds half their unused rent. Both prepaid rent
and stored inventory enter capital-employed reporting and ledger reconciliation.
The Ports warehouse disclosure offers leases, releases and transfers in either
direction for the selected docked ship. Transfers require an available berth,
charge handling (and liquid cleaning when collecting a different liquid), and
hold the berth through physical handling. Busy berths currently produce an
explicit retry message: automatic transfer queuing is deferred. Cargo changes
location atomically at acceptance, preserving cost and expiry and splitting lot
identities only for partial batches. Committed warehouse space is protected
until handling finishes. Stored cargo remains private to its company.

Expiry prevents new deposits and allows 12 active-world hours for collection.
Perishable aging continues. Expiry and clearance notify the owner. Until
receivership auctions are implemented, remaining cargo goes to system clearance at
50% of reference value, with grace rent deducted only from clearance proceeds.
Bankrupt-company storage follows the same clearance fallback after committed
handling finishes. All timings pause with the world. Liquidation auction stages and port-specific
warehouse tuning remain subsequent milestones.

Reservations are relational, typed claims owned by the warehouse aggregate.
Players earmark quantities of a cargo for a ship, or reserve receiving volume.
Stored stock is not counted twice; other ships cannot take earmarked quantities,
and unrelated deposits cannot consume reserved space. Matching transfers consume
reservations atomically. Optional route-stop links release immediately when the
stop is removed; unlinked claims last until collection, cancellation or expiry.
Spoilage reduces stock claims in creation order after assigning remaining fresh
stock; receiving claims end with the lease, while stock claims survive grace.
The current reservation UI does not yet specify a minimum remaining freshness.

Renewal quotes lock for the existing blocks during the final six active-world
hours. Players can pay for 1, 3 or 7 days; the new term starts at the old
expiry. Future prepaid rent is recorded separately and is not expensed before
that date. Only one subsequent term can be booked. Capacity reductions are
unavailable once the next term is paid. Optional auto-renewal takes a term and a
daily rent cap, checks free cash and unpaid bills, and retries on world ticks
before expiry. An extension prepays that same single term at any point before
expiry, quoted at current rates and confirmed on payment, for consignments and
bids whose auction closes after the current term ends. A prepaid term counts
toward auction storage coverage as soon as it is paid; enabling auto-renewal
alone does not. Renewal and extension report separate errors, so the six-hour
rule is never quoted at the extension form. Reservation, renewal and extension
controls use persistent, collapsed disclosures inside Warehouses, where the
stored-cargo table shows reserved lots beside stored lots; amounts and text
support English and Arabic.

## Diversions underway

Sailing ships can choose a new destination, including their departure port.
The preview displays a dashed revised course, revised time remaining, additional
fuel, released fuel and new canal charges. Confirmation leaves consumed fuel
spent, replaces only the remaining fuel reservation and atomically commits
funding and navigation. Insufficient funding leaves the old voyage intact.

Routing joins the current position to its current sea-network edge, then finds
the shortest path through the existing catalogue's sea segments. Diversion
waypoints are relational ship children and survive reload; another diversion
starts on that persisted path. Canal edges come from the same searoute dataset
as the catalogue. Previously paid Panama/Suez fees remain spent and are not
charged again during diversions of the same voyage. The normal next departure
starts a fresh toll allowance. Port instructions stay at their original ports;
a running repeating route is paused until explicitly resumed.

## Standardized cargo exchange

Ports expose a Cargo exchange disclosure for bulk commodities, mass consumer
products and scrap. Books match warehouse-backed player orders and the existing
finite NPC supply/demand adapter. NPC depth and budgets are shared with manual
ship trades; ship trading still uses that adapter rather than routing through
player warehouse orders. Perishables and auction cargo remain outside this book.

Buy orders escrow quantity times limit price and reserve compatible receiving
space. Sells reserve owned stock, excluding claims already earmarked for ships.
Warehouse-to-warehouse ownership changes, cost basis, profit, escrow release and
order quantities settle in one transaction. No exchange or handling fee is
charged for a warehouse ownership transfer. Subsequent ship collection pays its
normal handling fees. Price improvement is released immediately.

Matching uses best price then server acceptance time and revision, with a stable
ID tie-break. Player fills execute at the older resting price; own-company orders
never match each other. NPC offers have priority at equal prices and change at
25-lot depth boundaries. Placement and amendment each allow up to 512 fills. Tick matching shares a
512-fill budget across all orders and visits at most 512 orders. A rotating
in-memory priority cursor resumes after the last visited order, even if that
order was removed; restarts/reloads restart scheduling from the oldest order.
Counterpart selection retains price/time priority. Reconciliation and sorting
still inspect all open orders, so these budgets bound fills and visits, not total
tick CPU time. Remaining executable quantities retry on subsequent ticks. Orders are capped at 100 per
company, 1,000 per port/cargo book, and 10,000 lots each. The book retains only open orders and the last 20
public fills per port/cargo; the financial journal remains the durable audit.

Cancellation releases all unfilled backing. Quantity reductions preserve
priority, while increases and price changes reset it. Failed amendments retain
the old order and its reservations. Optional active-world expiry does not extend
a lease; lease expiry, missing backing and bankruptcy also cancel orders.
The UI shows aggregated player price levels, the NPC's current price level,
recent executions, and private order placement/amendment/cancellation controls.

## Luxury cargo auctions

The Ports column offers a collapsed Luxury auctions disclosure, with
consignment, sealed bidding, bid revision/withdrawal, and anonymous final
amounts. Bids are whole-lot totals, not prices per cargo lot, and reserves and
bids are entered in whole dollars; a seller revising a listing keeps an existing
fractional reserve unless they type over it. Player consignments require
available warehouse stock and lease coverage through closing, which a prepaid
next term satisfies. A rejection reports how far the lease falls short of
closing and how long warehouse handling still has to run, as separate sentences
and only where each applies, and a rejection for want of stock names the
warehouse rather than cargo aboard a ship. Sellers can change quantity and
reserve or withdraw before opening; afterward the commitment locks. Each company
has one active bid per listing. Amount changes reset acceptance priority;
unchanged amounts retain it. Cash and receiving volume remain reserved until
withdrawal, disqualification, or settlement. Failed revisions preserve backing.

Highest eligible bid wins, paying the greater of reserve and second-highest bid.
Ties use server acceptance time/revision and a stable ID tie-break. Losing cash
and capacity and winner price improvement release atomically. Whole-lot prices
are apportioned across immutable cargo batches without losing fractional cents
or resetting lineage. Auction transfer has no exchange or handling fee; later
ship collection uses normal handling. The winner receives a notice naming the
quantity, cargo, price and the warehouse the lot was delivered to, reading that
lease's storage class rather than assuming one, and it raises a system
notification the way a completed load does; the seller and the other eligible
bidders receive the settled notice. Bankruptcy cancels seller commitments and
disqualifies bids. Insufficient lease coverage is rejected before acceptance.

Schedule settings are application configuration under `:tijara_tides, :auctions`,
a map with string keys: `interval_ms` and `window_ms` both default to 86,400,000;
`offsets` can supply port offsets within the interval. Otherwise sorted port IDs
evenly stagger openings. Published times remain immutable. Windows and frequency
are independent. As elsewhere, time advances only while the world runs; the UI
shows active-world countdowns rather than promising a wall-clock closing time.

Computer suppliers list up to `supplier_lots` (default 5) from finite stock in
the next unopened window, with at most four concurrent supplier lots per market.
Outstanding supplier lots count against stock available for further listings;
luxury stock cannot be sold through the manual or standardized exchange paths.
Simulated consumer/merchant demand uses the market's finite demand and budget.
At close, `simulated_bidders` (default 3, range 1–20) draw reproducible private
valuations using a server-generated secret seed persisted with the lot around the local bid using `valuation_spread_percent` (default 20,
range 0–100). Only affordable valuations meeting reserve participate. Their
receiving capacity is the market's remaining demand; the winning purchase
consumes that capacity and budget. Supplier actors never bid on their own lots.
Export-only/untraded ports have no simulated buyers, disclosed before consignment.

Limits are 50 open consignments per company and 100 active bids per company,
with at most 1,000 active bids per listing. Each lot is at most 10,000 cargo lots.
The latest 20 completed listings per port retain anonymous final bid amounts;
older auction rows are pruned, while the financial journal keeps the audit trail.
Closing work settles all due lots before lease liquidation; it does not share
the standardized exchange's tick matching budget. Industrial machinery,
receivership auctions, and berth-side direct bidding remain later milestones.

The Cargo panel also provides a global luxury-auction browser grouped by status
by default, with an option to group by cargo. Open auctions start expanded;
upcoming and settled auctions start collapsed. It lists open, upcoming and
recently settled lots, with open bidding first, then closing time. Rows show
port, quantity, whole-lot reserve and active-world countdowns; a settled row
adds its sale price and, where the player bid, whether they won. Settled lots
are bounded to the twenty most recently closed world-wide plus the player's own
bids and consignments, since twenty closed lots are retained per port. Selecting
a port switches to the Ports panel and expands its auction section. Group
disclosures preserve their state through live updates.

Warehouse headings and selectors use localized port, dedicated cargo (or shared
storage type), and a persisted company lease number. Internal IDs remain the
command and persistence keys. Existing leases are numbered in creation order;
new leases use the next number above the company's surviving leases. Renewal
and clearance of other leases do not rename a surviving warehouse.

The lease selector offers one option per storage type, listing compatible cargo
(with ordinary storage abbreviated to "non-perishable solid goods").
Ordinary and refrigerated leases accept mixtures of their listed goods. Liquid
leases additionally require a dedicated cargo, chosen from liquid goods only.

Next-port instruction history displays the current journey only. Successful
departure marks completed/cancelled prior instructions historical, without
deleting their records. Active instructions remain visible. Legacy records lack
journey identity; migration retains their newest contiguous destination group
and active orders. Subsequent departures distinguish repeated visits exactly.
