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
Procurement auctions and player industry remain deferred.
Age-based maintenance is implemented alongside depreciation. Next-port instructions are implemented;
they execute ship-specific buy/sell actions on arrival rather than placing
standing orders on a shared exchange. Each instruction optionally expires after
1–43,200 active-world minutes from acceptance. Blank means unlimited. The Ships
panel preserves the expiry draft across ticks and shows its remaining time.
At the inclusive deadline, expiry runs before berth admission or new fills,
cancelling only the unfilled remainder with an owner-only notice. Cargo, spending,
settled trades, committed handling and the onward plan are preserved. Automatic
departure still waits for handling and other active instructions. Migration
`20260930000002_add_instruction_expiry.exs` adds the nullable typed deadline;
legacy instructions remain unlimited. Deadlines pause offline, survive reloads
and remain fixed when a creation request is replayed.

Next-port buys and repeating-route load targets also accept an optional minimum
remaining shelf life, in active-world minutes (0–43,200; blank means any unspoiled
cargo). Check it at purchase or collection settlement, not at predicted arrival.
Within each source, take the earliest-expiring qualifying lots first, retaining
lot identity, split lineage, acquisition cost and expiry. Owned warehouse stock
qualifying for the ship is used before market purchases, without consuming other
ships' reserved quantities. Unsuitable stock stays owned in place; no trade or
cash posting occurs when no stock qualifies. Fixed targets retry the remainder;
buy-maximum targets also wait when all available stock fails freshness. Route
load targets count only qualifying cargo already aboard, while all cargo still
uses physical capacity. Current visit orders retain their snapshotted terms when
the template is edited. Private controls, progress and waiting reasons persist
through replay and restart. Migration `20260930000003_add_instruction_freshness.exs`
defaults existing instruction and route terms to zero. Standing-order freshness terms, graded backing and markdown presets are now implemented; see below.

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

The selected owned ship has a procedural 3D berth scene while docked, loading
or unloading. Up to twelve dry containers occupy four deck slots and three
layers. Their count approximates transferred volume relative to hold capacity;
existing cargo stays visible underneath additions or after partial unloading.
The crane fills stacks from the bottom and removes boxes from the top, keeping
deposited cargo visible. Dock stacks sit behind a clear gantry rail lane; the
trolley reaches over them while the legs and wheels travel clear of the cargo.
These boxes illustrate fullness and handling rather than individual manifest
lots.

Tankers show a shore storage tank feeding a pump skid, with continuous pipework
to a counterweighted marine loading arm on a dockside pedestal. The arm connects
to a visible deck manifold and tank pipework. Its two rigid sections swivel with
the ship's bobbing, roll and changing draft, keeping the coupling attached while
cargo moves. Turquoise chevrons move along the outside of the opaque pipes toward
the ship during loading and toward shore during unloading. Pause and reduced
motion replace them with stationary directional arrows. The chevrons and the
shore-side pumping indicator disappear when transfer stops. After handling
completes, the arm lifts clear and folds back over the jetty; docked and queued
ships show it parked. Retraction does not extend the authoritative handling
deadline.

The ship bobs and rolls gently, with draft proportional to occupied hold volume.
Empty ships expose their red lower hull and Plimsoll mark; at full capacity the
mark meets the mean waterline. Dry ships settle smoothly as boxes lower onto the
deck and rise as boxes lift off, retaining the draft of cargo that stays aboard.
Tankers change draft continuously while pumping. Pause freezes draft as well as
the crane, and reduced motion suppresses bobbing and roll.

Ship transitions record the operation's start time and transferred volume in
litres alongside its completion deadline, and clear them atomically when handling
ends. They remain owner-only; no cargo volume is added to public ship views.
The renderer samples committed world time and scales the sequence so the last
box lands at the handling deadline, including when opened midway through an
operation. Tick updates do not restart it. Older operations lacking metadata use
one illustrative transfer across the remaining time when first shown.

Empty dry holds show no deck cargo. Queued ships show no transfer. All motion
stops after ten seconds without a changed snapshot, preserving the current
stack; the server remains authoritative for completion. Hidden and disconnected
scenes stop rendering. Reduced motion gives a still scene; pause suspends local
animation, and resume catches up to world time. Missing WebGL2 or context loss
retains a static illustration and the existing status text.

Three.js 0.186.1 and its MIT license are vendored under `assets/vendor/three`.
Mix/esbuild bundles the renderer as a separate ES module, loaded only when the
scene becomes visible. The regular application script is also an ES module.
No external models, textures or CDN requests are required. GPU resources are
disposed when changing ship, sailing or leaving the view. Browser contracts
cover rendering, loading/unloading, LiveView patches, pause, reduced motion,
disconnect/reconnect, hidden views and the static fallback.

The first market screen offers manual immediate trades against finite simulated
supply and demand for order-book cargo. Luxury and contract goods stay visible
in the catalogue; luxury goods trade through scheduled warehouse-backed auctions,
while machinery awaits procurement auctions. Quantities,
reference prices, production rates, ship prices, and travel scaling are explicit
provisional tuning values. Voyages currently run at 600× sailing speed with a
six-second minimum (10× faster than the initial playtest). Existing voyages are
retimed on their next tick, preserving progress and fuel already spent.
New ordinary shelf lives are provisionally 60 active-world minutes for fruit
(bananas), 90 seconds for meat and 60 seconds for seafood. Refrigeration defaults
to quarter-speed biological aging, giving fresh cargo 4 hours, 6 minutes and
4 minutes respectively. Rates and birth shelf lives live in the catalogue;
accepted holdings snapshot their conditions. Existing lots retain their original
shelf-life basis and biological age when upgraded. Higher reefer ship crew costs,
smaller holds and higher refrigerated storage rent supply the cost tradeoff.
Cargo holds immutable birth expiry and lineage separately from projected expiry
under its current conditions. Exact integer age units survive warming, cooling,
resale and splits; cooling cannot revive spoiled goods. Harvest time and biological
freshness never reset. Lifetime previews use the receiving hold on purchase and
show remaining time under current conditions in storage. Clearance payments use
biological freshness, with exact rational cent remainders across mixed birth
shelf lives. New
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
departing or rerouting clears it. Compatible cargo columns show green outbound,
yellow return and orange other-port symbols on one shared scale: circles price
a fresh purchase here, squares price cargo already aboard against the candidate
port's demand. Symbol
size is proportional to positive ROI, with hollow symbols for zero or
unavailable ROI and black skulls for negative ROI. Purchase ROI is the current
bid minus ask and both handling fees, divided by ask plus purchase handling.
Aboard-cargo ROI uses the recorded lot costs a sale would consume, in that order
and including a partial fill of the final batch; cargo whose recorded cost is
zero reports its proceeds with no ROI rather than dividing by nothing. A good
stays in the matrix when the hold is the only reason to visit, with no local
stock required. Return symbols take priority over other-port symbols in the same
cell; hidden onward opportunities do not affect the shared ROI scale. Orange
symbols show the best ROI for a load from the candidate destination to another
reachable port, excluding the current port, and keep cargo columns visible even when only an onward trade is available. Hover/focus
exposes ROI, lots, aboard-cargo proceeds and the best onward port. These
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

Raw-resource producers replenish finite stock, including locally grown spices.
Manufacturers use the explicit `manufacturing` recipes in the catalogue. Each
production cycle consumes the listed inputs from finite port inventories and pays
local production costs plus the current input asks from the producer's budget.
Input sellers receive the input payment. Both input and output stores are good-specific
and capped at 500 lots. A producer stops when any input, output space, or funding
is missing. Industrial buyers retain deliveries as feedstock rather than consuming
them as final demand. New worlds allocate 50 lots to otherwise empty industrial
input stores and retain the existing 500-lot producer output allocation; existing
worlds activate input demand without minting replacement starting stock on reload.
Recipes and the 10%-of-reference local costs are provisional tuning, including
catalogue substitutes such as recovered plastics for synthetic fibres. Re-export
merchants now use paid warehouse-backed inventory (described below).
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
reservations, renewals and extensions are available. Earned invitation
allocations grant one per two active-world days of active, solvent operation.
Warehouse-backed standing exchange orders are
available for standardized cargo. Next-port cargo instructions and optional
automatic departure are available. Operating shortfalls accumulate as unpaid
bills and participate in the implemented loan settlement and bankruptcy rules.

Launch invitations grant three outgoing invitations; ordinary invitees initially
have no outgoing quota. All players can earn invitations through qualifying
economic actions worth at least $100, including automated trades. Each action
keeps a company active for two active-world days; forming a company, signing in,
and drawing credit do not qualify. Earning requires an unsuspended owner, an
operating company, no unpaid bills, and no loan arrears. Inactivity, financial
trouble, or a replacement company resets partial progress. Available plus
outstanding invitations are capped at three, with no banked progress while full.
Progress and quota commit atomically and survive reloads. Players receive a
localized notice with each earned grant, pointing to the account menu. The notice
commits with the grant and is not repeated by retries. Existing companies
start with their next qualifying action, without retroactive credit. Unused
invitations expire after three active-world days
and restore their inviter's quota. Device sessions expire after one wall-clock
year. Before redemption, GET /play delivers a private random device credential
in the signed, HTTP-only cookie. A lost redemption response can be retried using
that same credential, including after server restart. Another device holding
only the invitation cannot recover the account; revoked or expired credentials
cannot be revived. POST without the pre-issued cookie consumes nothing.
Operators can grant one to three additional invitations to an existing,
unsuspended account by account ID or verified email. The grant fails in full if
available plus outstanding invitations would exceed three. Quota and a durable
operator receipt commit together; repeating the same request returns its original
result, and reusing its ID with a different target or count is rejected. Grants
do not record a player visit or economic activity. See the
[operator command](database.md#operator-invitation-grants).
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

- **Simulated economy:** differentiated production rates, money-stock and
  source/sink monitoring, and price-level monitoring (§5).
- **Procurement:** machinery delivery auctions, supplier deposits, buyer funding
  and receiving-capacity commitments, delivery deadlines, settlement/default and
  system-fault protections (§7).
- **Unified markets:** direct ship trades against player order books (§§6–8).
- **Ports and physical handling:** full ship-size, terminal and waterway limits,
  predictive queue estimates, automatic warehouse-transfer queuing, transfers
  between storage types, and utilization-triggered berth/storage growth with
  published construction lead times (§§4, 10, 11).
- **Accounts and disclosures:** Google identity linking, asset-triggered linking
  prompts, concrete suspicious-trade and
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

The map at the top of the Cargo panel is flanked by Supply and Demand emoji
strips listing the same cargo as the selector. The map turns red exactly the
ports that `cargo_markets/6` lists for the selected cargo and side, the same
rows as the table below it. The LiveView keeps only the side (`map_cargo_side`)
and reads the cargo from the selector, so the highlight follows any cargo
selection. An emoji is disabled when that cargo's option has no ask (supply) or
no bid (demand); both come from the same `cargo_markets/6` rows. The compact
regional view hides the strips in CSS; the highlight remains.

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
limits survive database reloads. Receivers unload cargo into finite compatible
storage after voyages and handling finish, then offer warehouse cargo and empty
ships through sealed second-price auctions. Open consignments continue; new
estate listings cannot be bid on by the previous owner’s replacement company.
Payments and residual cash leave the economy. Unsold cargo is removed and unsold
ships are scrapped. Necessary storage/handling costs use available estate cash;
the receiver absorbs shortfalls without adding arrears. Used ship purchases retain
hull age and maintenance history while recording acquisition cost separately.
The new cost depreciates over remaining useful life (at least one active day),
with a 20% residual. Estate reserves use 10% of cargo reference or ship book value;
these are provisional tuning constants. Perishables use a two-hour expedited
window if they survive it; otherwise the receiver disposes of them immediately.

## Verified email identities

Players can link an email from the account menu. Email verification appears above
Invitations; sending invitations stays hidden until an email is verified. Players
with no available invitations see an earning countdown or the action needed to
resume earning, plus the earliest unused invitation expiry, even before email
verification. The owner-only forecast uses saved progress and the active-world
clock; it does not award quota or alter progress. Earning estimates assume
continued active, solvent operation, and expiry estimates assume the invitation
remains unused. Once linked,
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
Linked fixed buy targets reconcile unfinished, uncommitted visit orders and
standing-order backing together; rejected edits retain the previous terms.
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
cleaning. Without an optional advance budget, purchases use unreserved cash.
Prices use the same limit semantics and
voyage-affordability checks as manual and single-visit trades. Partial fills retry
and never accumulate across circuits. Once sales finish, exhausted hold capacity
cancels the remaining loading shortfall with notification. Other unfilled targets
wait until filled, explicitly cancelled, or their stop's maximum wait elapses.
Linked exchange orders and advance purchase budgets are described below.

Each stop has an optional maximum wait, configured in minutes (up to 30 days)
inside its collapsed Wait limit disclosure. Blank means unlimited waiting.
The active-world deadline is saved from arrival, including berth queues and
handling, and survives retries, partial fills, phase changes, pause/resume and
database reload. Starting a route at its current port starts the visit then;
starting while sailing uses its actual arrival. Limit edits apply to visits
that have not arrived yet and never change the current visit's saved deadline.
At the inclusive deadline, timeout runs before berth admission or new route
fills. Unfilled targets are cancelled, including purchases whose sale phase has
not finished, while committed handling drains without starting another phase.
Then the ordinary automatic-departure and stop-after-visit rules apply; funding
blocks remain separate. The editor shows an active-world countdown and retains
the latest timed-out visit's cargo shortfalls through its private notice even
after departure. Unlimited existing stops retain their behavior. Migration
`20260930000001_add_route_wait_limits.exs` adds typed stop limits and visit timers.

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
Departure warnings identify each unfinished cargo instruction at that visit by
cargo, side and port, show filled and remaining lots, and include its current
waiting reason. Future-port and completed or cancelled instructions are omitted.
The same warning appears in queued departures, onward plans and repeating routes.

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

Expiry prevents new deposits and cancels incoming buy orders. The default grace
period is 12 active-world hours for sale or collection. Perishable aging
continues. At grace end, remaining usable goods fill compatible local player buy
orders in price/time order, then enter computer-run liquidation auctions. Owner
minimum sale prices do not constrain these sales. Ordinary lots use the next
scheduled port auction with its full window; perishable lots use a fixed two-hour
window. Cargo unable to survive that window clears immediately. Unsold auction
lots clear at 10% of configured reference value, multiplied by the remaining
biological shelf-life fraction for perishables, capped at one. Spoiled cargo is
discarded without payment. Fractional clearance amounts carry across batch and
lot splits within the lease pool. Clearance leaves storage and the economy;
existing finite simulated auction buyers retain their shared demand and budgets.

Each expired lease has a durable accounting pool. All forced-sale proceeds stay
in reserved cash until its cargo and commitments finish. Grace storage uses the
previous lease rate per occupied block; liquidation adds a fixed 25% surcharge.
Only occupied blocks continue accruing charges, and each released block leaves
port utilization immediately. Unpaid storage and clearance handling are capped
by the aggregate proceeds of that lease. Warehouse ownership transfers through
buy orders and auctions add no handling fee. Shortfalls create no payables and
never debit other cash or another lease's proceeds. Completion pays nonnegative
net proceeds to a solvent owner. Bankruptcy during this process preserves its
auctions and charge pool; outstanding net proceeds instead leave the economy.
Bankruptcy asset auctions retain their separate rules.

Lease rows snapshot grace, surcharge, expedited window and clearance rate from
`warehouse_liquidation` catalogue settings (`grace_ms`, `surcharge_bps`,
`window_ms`, `clearance_bps`). Changing defaults does not rewrite accepted terms
or running deadlines. Owner notices disclose both storage rates; the storage UI
shows the grace countdown, held proceeds and accrued charges. Auction listings
show liquidation status and projected freshness without exposing private lease
identities. State, reservations, cargo lineage, escrow and postings commit in
one transaction and resume after reload. Perishable standing books and
port-specific warehouse tuning remain separate milestones.

Cargo auction awards receive separate storage allocations in the supporting
lease's physical space. Their snapshotted grace starts at the later of actual
settlement and paid coverage expiry, using the active-world clock. A timely paid
extension extends that support before grace starts. Shared allocations count
aggregate occupied volume and current paid blocks once; they cannot receive new
cargo or acquire additional blocks. Other expired stock keeps its own deadline.
During grace, replacement pays the current progressive new-lease quote for the
remaining occupied blocks plus accrued storage charges. A fresh paid lease starts
immediately, preserving lot identity, standing-order priority and auction terms.
Failed payment changes nothing. The old charge pool retains its payment history,
and a later expiry of the replacement creates a separate liquidation pool.

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
the standardized exchange's tick matching budget. Industrial machinery and
berth-side direct bidding remain later milestones.

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
(including perishables in ordinary storage).
Ordinary and refrigerated leases accept mixtures of their listed goods. Liquid
leases additionally require a dedicated cargo, chosen from liquid goods only.

Next-port instruction history displays the current journey only. Successful
departure marks completed/cancelled prior instructions historical, without
deleting their records. Active instructions remain visible. Legacy records lack
journey identity; migration retains their newest contiguous destination group
and active orders. Subsequent departures distinguish repeated visits exactly.

Next-port purchase suggestions use the manual purchase command's remaining hold,
fresh-stock and funding checks, including the selected onward voyage and the
visit's budget or skip decision. Before arrival they deduct the known inbound
fuel, canal fees and estimated fleet upkeep; already reserved voyage fuel is
counted once. The snapshot projects arrival time without assuming replenishment,
sales proceeds or future income. Choose and save an onward destination before a
purchase quantity is suggested.

Owned warehouse stock takes priority over market purchases through the same
source-selection rule as execution. Its suggested quantity and purchase cap use
collection fees, unclaimed qualifying stock and onward funding. Sale suggestions
use the smaller of cargo aboard and current cash-backed demand. Explicit price
limits remain editable and may intentionally wait for a price change. Suggested
quantities and spending caps reserve no resources; later trades, delays and
changing quotes can still prevent complete filling or departure.

### Participation-scaled economic depth

Each live company has one economic weight, capped at 1, decaying exponentially
since its last qualifying action over seven real days. The index sums these
weights globally; fleet size, port selection and authentication do not increase
it. Settled trades, funded auction bids, ship purchases, dispatches and paid
warehouse terms qualify at $100 or more. Automated economic actions count;
owner absence and dormant closure use the separate lifecycle described below.
Failed commands, receipt replays, bid withdrawals and operating expenses do not
refresh participation. Timestamps commit atomically with the economic action.

The global index scales producer and factory cycles, consumer demand recovery,
and buyer-budget replenishment. Fractional production credits persist across
ticks/reloads, while physical 500-lot storage bounds remain in force. Budget caps
are one game quarter of the current scaled replenishment rate. Zero participation
stops replenishment; existing inventories remain available to restart trading.
The `participation` catalogue settings configure decay, minimum action value and
budget quarters. Existing companies start without fabricated activity history.

### Warehouse-backed re-export merchants

Merchants lease good-specific compatible space from the same finite port pools
as player warehouses. Three-day rent is paid from their finite market budgets;
they seek renewal with one day remaining. Insufficient funds or space suppresses
new purchases and offers. Unrenewed storage is locked at expiry and cleared after
12 active hours. The provisional target is ten lots per merchant, rounded up to
whole warehouse blocks (`merchants.storage_lots` in the catalogue).

Merchant purchases retain the actual delivered batches, including lot identities
and expiry, and resale transfers or splits those same lots. Ship loading and
unloading protect merchant storage until handling finishes. They never replenish
stock through production. New merchants start empty; legacy acquired stock is
materialized once into durable batches rather than copied from a producer.
Quotes cap demand by paid free space and budget, and supply by uncommitted owned
stock. Merchant leases contribute to player-facing pool occupancy and rent quotes.

Luxury merchants buy through the existing finite simulated auction bids; those
bids are admitted at settlement only when funds and paid receiving space cover
the lot. Newly acquired stock can be offered only in a later unopened auction.
Listed quantities are excluded from other offers, and a merchant cannot bid on
its own listings. Consumer purchases remain the final consumption sink.

## Linked remote orders and departure funding

Fixed buy targets for Bulk commodities, Mass consumer products and Scrap may
link to an owned compatible warehouse at the stop. Demand subtracts qualifying
cargo aboard and available owned stock, respecting other stock reservations.
The linked order reserves its own cash and receiving capacity. Each completed
fill becomes owned warehouse cargo earmarked for the collecting ship and stop.
It cannot become another ship's collection or sell backing. Original lot IDs,
acquisition cost and expiry survive transfer. Ordinary unlinked orders remain
independent. Perishable standing books and their linked targets use the same cash/capacity backing and inherit the rule's minimum remaining life.

At berth assignment, one atomic handover cancels the remote remainder and
releases its cash and incoming capacity, retaining completed stock claims for
collection. The visit collects owned stock before buying its shortfall. Linked
orders cannot compete for another fill after berth assignment or the inclusive
maximum-wait deadline. Target reductions release excess backing; increases and
repricing validate fresh backing before committing the target and order together.
Committed handling is protected. Removing a link/stop or ending a visit releases
claims while retaining purchased cargo. A completed circuit rearms each target
once, without carrying forward unmet quantities. Unaffordable future backing
retries without duplicating reservations. Private notices report the cancelled
remainder, cash returned and stored stock retained.

An optional per-stop advance budget reserves purchase cash separately from fuel
and standing orders. It is a strict cap including market handling and cleaning;
market purchases, including manual buys during that visit, cannot supplement it
from free cash, sale proceeds or linked-order refunds. Owned-stock collection
fees use ordinary available cash. Explicit budget changes respect cash and
settled spending. Unused funds return when the visit finishes, expires or is
removed. Repeating stops retain their configured amount, funding only the
current initial visit at start and the next visit together with departure.
Single next-port visits can also reserve an explicit budget.

The Fleet panel offers one account-wide insufficient-funds policy: Wait and
notify (default), Sail with a reduced budget, or Skip purchases. Each policy
fully funds fuel and canal fees. Reduced budgets remain strict at arrival; Skip
still permits deliveries and owned-stock collection. Affordable departures are
allocated by original waiting age, with stable ship-ID ties; an expensive older
request does not block an affordable younger one. A policy change re-prices
waiting requests in place: waiting age and window deadlines are kept, and
accumulated cash above the new requirement is returned. Blocked/resumed notices
are coalesced. Reservations and departure share the authoritative atomic
operation.

After 30 active-world minutes, the oldest eligible request may accumulate cash
for a fixed 10-minute window. Only one ship per company accumulates. Arrears and
loan installments settle first. Completion converts the accumulation into the
ordinary fuel/purchase reservations once. Timeout returns cash, settles arrears
and funds affordable departures before another accumulation, with a 30-minute
cooldown and preserved waiting age. Retries and partial funding retain the
original deadline. The `:departure_funding` application setting configures
`wait_ms`, `window_ms` and `cooldown_ms`; the domain validates positive durations.

Migration `20261001000000_add_route_funding_and_links.exs` stores private linked
cycles, visit budgets, departure requests, account policy and route completion.
Reload and receipt replay preserve reservations, waiting age and deadlines.
The financial verifier includes fuel, visit and accumulation reservations;
conflicting cash releases roll back the transaction. Tests cover NPC, player and
liquidation fills, strict budgets, fair allocation, timeout, plan changes,
receivership, database reload, command replay and rollback.

## Owner absence and dormant closure

Owner interactions coalesce into at most one ordinary dormancy visit per wall
minute. Gameplay commands include the visit in their own commit; rapid form
events do not cause separate writes and broadcasts. Returns during a warning
cancel that warning immediately, even within the throttling interval.

Dormancy uses durable wall-clock timestamps per company, separate from economic
activity. The default absence interval is 30 real days followed by 7 real days of
advance warning. `TIJARA_DORMANCY_ABSENCE_DAYS` and
`TIJARA_DORMANCY_WARNING_DAYS` configure positive whole-day intervals. An issued
warning keeps its original closure deadline even if settings change.

Authenticated page loads, email sign-in and explicit player actions reset absence;
snapshot reads, websocket reconnects, connection heartbeats, automatic UI events
and economic automation do not. UI-only actions share the coalesced asynchronous
refresh task. Successful gameplay commands also persist visits atomically. A
return before the deadline cancels the pending warning notice and queued email;
a return at or after the deadline cannot restore the old company.

Linked accounts receive retryable warning email with an absolute UTC deadline
and a game link. The warning is not a sign-in credential. Unlinked accounts have
in-app notice only; the account panel states the inability to receive external
warnings and the consequences of losing the device session. Delivery failure or
an unread warning does not postpone closure. A full warning interval starts when
the warning is recorded; a late first check never backdates it.

A minute-level wall timer runs even while simulation progression is idle. Startup
honours existing expired warnings before publishing the restored world. Voyages,
cargo aging and asset liquidation still use the active-world clock. Existing
companies without an absence record start a fresh baseline at their first check.

Closure cancels ship automation and order-book commitments, releases invalid
auction bids, detaches the account and removes economic activity. Ships and cargo
enter the existing receivership process; residual estate cash leaves circulation.
Dormant closures persist in `game_company_dormancy`, separate from bankruptcy
events, and add neither a bankruptcy count nor a restart cooldown. Sponsor
guarantees still settle against debt recorded at closure. The legacy
`bankruptcy_ms` company field serves as the shared receivership marker; public
closure reasons and owner notices distinguish dormancy from bankruptcy.

Expired-lease liquidation now follows the order-book, auction and clearance
sequence described above, with durable per-lease charge caps. Won-cargo grace
and replacement leases use isolated allocations and preserve those caps.


## Freshness-graded standing books

Perishables now use the standing warehouse book. Biological freshness has four
provisional grades: Fresh (at least 75%), Good (50–75%), Fair (25–50%), and
Clearance (below 25%, still unspoiled). Buyers can require a minimum grade and
remaining active-world lifetime, checked in their receiving storage. Linked
remote buy orders copy the route rule's lifetime requirement.

Each sell order retains one stock claim with separately priced lot portions.
Only a portion whose grade or price changes loses priority; unchanged portions,
partial-fill descendants, and quantity reductions keep it. Expired backing
shrinks the remaining order without selling spoiled goods. Claim-aware stock
extraction preserves other orders' allocations.

Optional complete four-grade markdown schedules use a copied initial asking
price, rounded upward to a cent, with an optional absolute floor. No schedule
means the asking price stays fixed. Explicit rebasing affects remaining portions
and resets priority. Preset names are trimmed and limited to 80 Unicode code
points, matching the PostgreSQL constraint, and reject Unicode control and format
characters. New presets use a server-generated identifier; a supplied identifier
must name an existing preset owned by the caller. Players may save up to 50 account-owned
presets and apply copies to selected orders or one-visit automated sell instructions. Editing or
deleting a preset leaves applied terms unchanged. Automated sales release only
lots whose grade minimum is met by the port bid; other cargo stays aboard.
Migration `20261001000003_add_graded_books.exs` persists settings, portions,
priorities and presets. Books and owner controls disclose grade and remaining
life; accepting an amendment atomically replaces cash and cargo/space backing.


## Port and cargo handling speeds

Physical loading, unloading, owned-stock collection and warehouse storage now
use the port roster's speed capability and cargo type. Provisional time per lot
is 500/350/250 ms at slow/medium/fast ports. Perishables use 125% of ordinary
handling time, scrap 150%, and pumped liquids 75%; each operation takes at least
one second and fractional milliseconds round upward. These configurable values
live in the generated catalogue's `handling` tuning. Tank cleaning still adds
its existing separate minute and cost.

The shared duration calculation also supplies trade/purchase affordability,
mixed-manifest route estimates and receiving-port unloading freshness previews.
Ports publish representative handling times, and trade controls show the
selected quantity's duration. Accepted handling keeps its stored finish time
through reload; berth and warehouse protection use that same deadline. Remote
exchange ownership transfers still incur no physical handling time or fee.


## Regional weather and revised voyage estimates

Staggered storm schedules use an independent hash scaled across the full
available start interval, rather than clustering in the beginning of each window.

Weather now uses deterministic active-world storm windows in 24 geographic
sectors, partitioning the actual sea path at sector boundaries, including the
dateline. Provisional tuning gives each sector a 10% storm chance per 30-minute
window, with a one-minute storm at a deterministic staggered start. The initial
window is clear. The generated catalogue controls probability, period, duration
and seed; `config :tijara_tides, :weather` may override those defaults. Storms
occupy at most a quarter of their window, with a clear interval.

Dispatch and purchase planning include currently known storms encountered along
the route. Subsequent announced storms revise the arrival estimate underway.
The ship snapshots its path, sailing duration and weather model; its bounded
per-voyage pause timeline and current regional warnings persist in migration
`20261001000004_add_weather_delays.exs`. Repeating ticks and restarts reconstruct
the same timeline. Legacy voyages acquire weather only from their first observed
weather tick, preserving previously travelled distance and fuel consumption.
That first tick persists the reconstructed sea path; later catalogue geometry
changes cannot rewrite the voyage's accepted movement.

Actual movement, map markers, diversion starting points, fuel settlement, crew
estimates and cargo arrival/unloading freshness all use the same pause timeline.
Fuel consumption stops during weather waits; idle crew pay, refrigeration aging
and maintenance continue. Storms cause delays without randomly losing cargo or
ships. Cargo may still spoil through the normal aging rules. Ports publish
current storm countdowns, dispatch previews show known delay, and public ship
inspectors and owner fleet controls show weather waits and revised ETAs. Owners
receive a structured notice when weather changes the estimate. No private
manifest, cost or financial information is included in public weather disclosure.

Funding revalidation indexes ready plans by ship and pending instructions by
ship/port once per pass. Sailing forecasts snapshot JSON-compatible weather
segments per voyage, including the first reconstruction of a legacy voyage;
ticks reuse these segments, while a new departure or diversion builds its own.
Operation-count tests bound instruction reads and route partition calls, and
cached forecast tests compare results across paths, seeds and warning cutoffs.
