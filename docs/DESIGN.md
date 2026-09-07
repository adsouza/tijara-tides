# Tijara Tides — Game Design

Status: design baseline consolidated from the product discussions on 2026-09-06
and 2026-09-07. This describes intended gameplay, not implemented functionality.
Decisions below are agreed unless explicitly marked provisional or open. Numbers
without final balancing decisions are deliberately left unspecified.

## 1. Vision and player experience

Tijara Tides is a multiplayer marine cargo trading game set in the modern world.
Players build lasting companies by buying goods, transporting them between real
cities in their own ships, and selling them for profit. Later, they can build
mines and factories at cities to produce goods themselves.

There is one continuous shared world with no scheduled resets. Players compete
through markets, fleet deployment, and eventually production. The ambition is to
make money and operate an efficient company, rather than win a finite match.

The game supports check-ins throughout the day and engaged sessions of up to
roughly 20 minutes. Voyages progress unattended; meaningful activity comes from
comparing markets, managing port cargo, bidding, arranging finance and storage,
and planning several ships. Manual ocean navigation is not required.

The initial loop is buy cargo → choose a destination → sail → sell → reinvest.
Remote trading, arrival instructions, and repeatable routes extend this loop.

## 2. Accounts, companies, and persistence

- Players use durable accounts with authenticated device sessions; browser guests
  are insufficient. Creating an account does not require an external identity.
- Creating an account requires an invitation from an existing player.
- Initially, each account operates one active company in the shared world.
- The company owns cash, ships, cargo, leases, loans, and later facilities.
- Accounts survive company bankruptcy and retain previous company history and a
  lifetime bankruptcy count.
- Signing out does not erase assets. While the world server remains awake,
  voyages, markets, cargo aging, ongoing obligations, and future factories
  continue for offline owners, including the idle interval after the last player
  disconnects. Hosting suspension pauses the world under the shared clock
  policy in section 3.
- Ownership and private-data access are enforced by the server.

Authentication is passwordless. Redeeming a valid invitation creates a durable
account and establishes its session on the current device, without requiring an
email address or Google identity. Preserve that device's session across normal
app or browser restarts. The account and company are server-side persistent
state, not disposable guest data.

Players may link an email address and/or Google identity to one durable account
at any time, after verifying ownership of the method being linked. Email
magic-link sign-in is supported on both web and native Linux; Google sign-in is
additionally available on the web, and the Linux client must not depend on it.
Neither method is mandatory to begin playing. Either linked method restores
access on another device to the same account, company, and bankruptcy history.
Redeeming an emailed invitation magic link also verifies and links its delivery
email as part of account creation; merely specifying an address does not verify
it. Later linking does not create another company or reset account history.
Shared company management is a later possibility, not part of the initial design.

An account with no linked identity exists only as a device session. Prompt the
player to link one once their company holds meaningful assets, using a configured
value threshold, and repeat the prompt periodically while the account stays
unlinked. State both consequences plainly at that prompt: losing the device
session ends access to the company permanently, because nothing else can prove
ownership, and the account can receive only in-app notices, so out-of-band
warnings, including the dormant-closure warning in section 5, cannot reach it.
Neither consequence is a penalty; both follow from having no verified identity to
recover through or contact. Linking at any later time removes both. The threshold
and prompt cadence are tuning parameters.

Account creation consumes an invitation issued by an existing player. Invitations
are earned through sustained play, provisionally one per completed game year
operating actively and solvent, rather than granted at signup. Earned invitation
entitlements belong to the inviter and cannot be transferred between accounts.
The resulting invite codes can be shared with prospective players. Invitations
expire if unused, and each account holds only a small number
outstanding, so they cannot be hoarded and released as a coordinated wave of
accounts. A configured set of seed accounts roots the tree at launch. Browsing
the public world without an invitation remains available: the invitation gates
company creation, not spectating.

An inviter chooses one of two modes, each reserving one available invitation
entitlement:

- **Email invitation:** supply the recipient's email address and have the game
  automatically send a single-use invitation magic link. When the recipient
  opens and redeems that link, create the account, establish its device session,
  and automatically link the addressed email. No separate email-linking step is
  required. The inviter sees delivery status and expiry, but never receives the
  email-verification link or an equivalent credential that could authenticate as
  the recipient. A separately shareable code is not issued for this mode.
- **Shareable code:** generate and display a copyable invite code for SMS or any
  other channel chosen by the inviter. Its first holder can redeem it to create
  an account and device session without any linked email or Google identity.
  The player can link an identity later.

Both modes admit one new account and expire after a configured period of a few
real days, displayed to the inviter and in emailed invitations. Invitation expiry
follows the shared world-clock outage policy. Only redemption strictly before
expiry succeeds. An email already linked to an existing account must not create
a second account or merge accounts through this flow; direct its owner to sign
in instead, without consuming the invitation entitlement.

An inviter distributing a code through an open channel is lending their own
credibility to whoever redeems it, by design. The tree records the inviter
however the code travelled, and the issuance consequences below apply to the
resulting subtree either way, so choosing to broadcast a code rather than hand it
to someone known is the inviter's risk to take.

Successful redemption consumes the reserved entitlement and records the issuing
player as inviter regardless of mode. Expiry of an unused invitation invalidates
its code or link and restores the entitlement to available quota. Redemption and
expiry must resolve atomically: one invitation cannot create multiple accounts,
and an entitlement cannot both be consumed and refunded. Retrying an expiry does
not restore quota twice. Copying a code or retrying email delivery does not
reserve another entitlement or extend its deadline.

Notify the inviter when their invitee successfully creates an account, for either
invitation mode. Identify the redeemed invitation and include the invitee's
company name with a link to its public company profile when available. If company
creation follows account creation, first report that the invitation was accepted,
then notify the inviter of the company name and profile once the company exists.
Do not report an attempted or failed redemption as a successful signup, and do
not duplicate notifications on retries. Use public company information only;
invitation relationships do not grant access to private cargo or instructions.

After redemption, the device session provides access to the account; the consumed
invite code or invitation link cannot be reused to sign in or recover it. A
linked identity provides cross-device access and recovery if the original device
session is lost.

Record the inviter-to-invitee relationship permanently. Beyond rate-limiting new
accounts, the tree gives the suspicious-trade review in section 12 a structure to
work against, since trade and bid activity concentrated inside one subtree is a
far stronger collusion signal than the same activity spread across strangers.
Repeated confirmed abuse within a subtree reduces the inviter's future issuance.
Issuance rate, outstanding cap, and expiry are configurable tuning; the
requirement for an invitation is not.

## 3. Time and competition

The world uses accelerated game time. Company assets persist across reporting
periods. One game quarter lasts one real week of world operation, and one game
year lasts four real weeks. Use a 52-week game year and a shared published
reporting calendar, anchored to a configured world-start epoch.

Every duration in this document is real time unless it is explicitly a game
period. Voyages, leases, grace periods, cooldowns, auction windows, and arrears
deadlines are real; reporting quarters and years are game periods mapping onto one
and four real weeks respectively.

Two families of parameter are deliberately expressed in game time, because they
are calendar-scale concepts that would be absurd read as real time. Ship and
facility useful lives, residual values, and depreciation schedules in section 13
run in game years, so a hull with a twenty-game-year life lasts about eighty real
weeks. Loan interest rates and installment schedules in section 12 are likewise
quoted per game period, with installments falling on a game-quarter cadence and
therefore about one real week apart. Wherever a player commits to one of these,
display the game period and the corresponding real interval together, so nobody
mistakes a twenty-year loan for a twenty-real-year obligation.

The shortest direct routes must take less than 15 real minutes under normal
conditions, including with the slowest ship eligible for those routes. This lets
a ship departing near the player's final interaction finish a short voyage
during the host's idle interval before suspension. Loading, berth queues, and
weather can extend the full port call beyond that interval; completion before
suspension is a normal-condition pacing goal, not an availability guarantee.
Regional voyages of several hours and ocean crossings of 12–24 hours remain
pacing suggestions. Balance navigable sea routes and ship speeds so that even
the slowest ship's longest direct port-to-port voyage takes no more than 24 real
hours under normal conditions; shorter is fine. Weather delays and port queues
may add time beyond that normal voyage ceiling. Exact shorter-route durations
and operating costs remain tunable.

Timers fall into two families, and they behave differently across a pause.

**World timers** measure in-world processes or commitments the world made to a
player: voyages, cargo aging, expenses, auctions, leases, grace periods, berth
re-entry and other operational cooldowns, contract deadlines, invitation expiry,
the bankruptcy restart cooldown, and reporting periods. During hosting
suspension or game-wide outages, pause all of these together. Resume from the
paused state without elapsed-outage catch-up, and update displayed deadlines and
the reporting calendar accordingly. Their real-time durations therefore count
time while the world is operating. Advancing them through an outage would
destroy cargo, leases and contracts a player had no opportunity to defend.

**Player timers** measure a person's behaviour rather than anything in the
world: owner absence and its dormant-closure warning period in section 5, and
the decay of a company's economic activity weight. These run on wall-clock time
and never pause. A player's absence is a fact about the real world and does not
stop because the server slept, so pausing these would break them in exactly the
conditions that matter. In a sparsely populated world the server is suspended
most of the time, so world-clock absence would accrue at a small fraction of
wall-clock: an absence threshold of two quarters could take months to expire,
dormant closure would rarely fire, estate cash would never leave circulation,
and simulated demand would stay sized for players who had already left.

Evaluate player timers against durable timestamps rather than accumulated
counters, so a pause of any length needs no reconciliation. On resume, close any
company whose absence and warning period both elapsed while the world was
suspended; section 2 already requires telling unlinked accounts that their
warning cannot reach them, and an unreachable warning is not a reason to defer
closure. Recompute activity weights from the same timestamps, so demand scaling
reflects who is actually still playing.

Player disconnections do not immediately pause the world: simulation continues
while the server remains awake, including the idle interval after the last player
disconnects. Persist completed progress during this interval. After suspension,
resume from durable state when a player reconnects and the world is ready.
Health checks and other non-player requests alone do not resume a paused world.
There is no offline catch-up for time spent suspended or otherwise paused.
Published real-time estimates assume the world
stays active; pauses extend their wall-clock completion times.

There are four leaderboard rankings: quarterly profit, quarterly ROI, yearly
profit, and yearly ROI. Rankings show the player's lifetime bankruptcy count.
Established companies can excel at absolute profit; efficient newer companies
can compete on ROI. Company history remains accessible after bankruptcy.

Rank absolute quarterly profit only for the three most recent completed quarters.
Beyond that horizon yearly profit is the relevant absolute measure, and completed
game years are retained and ranked without a comparable cutoff. This is a
relevance decision rather than a correction for drifting prices: the price-level
anchor in section 5 keeps nominal results comparable across the world's entire
history, so no leaderboard needs an inflation adjustment.

## 4. Geography, map, and visibility

Use real cities and ports, realistic geography, and sea routes that respect
coastlines, straits, and usable canals. Show ship positions and routes visually.
Distances and travel progress are geographic calculations independent of the
display projection.

**Do not use Mercator.** Use Equal Earth for the world map. Ships and ports are
clickable, with route overlays and a port panel showing markets, auctions,
storage, and congestion. Pacific crossings must
display continuously across the map seam rather than as false cross-world lines.
The user has requested these 25 locations for inclusion, superseding the rough
24-port scope: Shanghai, Singapore, Shenzhen, Guangzhou, Busan, Rotterdam,
Los Angeles, Dubai, Hong Kong, Antwerp, Tangier, Ho Chi Minh City, New York City,
Jakarta, Hamburg, Colombo, Mumbai, Manila, São Paulo, Valencia, Abu Dhabi,
Colón (Panama), Athens, Tokyo, and Houston.

Approved city-to-port mappings:

| City             | Harbor                         | Notes                                                                                                |
|------------------|--------------------------------|------------------------------------------------------------------------------------------------------|
| São Paulo        | Santos                         |                                                                                                      |
| Athens           | Piraeus                        |                                                                                                      |
| Shanghai         | Waigaoqiao and Yangshan        | Size-gated; Yangshan lies offshore on Xiaoyangshan Island, roughly 32 km out via the Donghai Bridge. |
| Shenzhen         | Yantian                        |                                                                                                      |
| Guangzhou        | Nansha                         | Pearl River estuary, roughly 60 km south of the city.                                                |
| Ho Chi Minh City | Saigon and Cai Mep             | Size-gated; see below.                                                                               |
| Jakarta          | Tanjung Priok                  |                                                                                                      |
| Mumbai           | Jawaharlal Nehru / Nhava Sheva |                                                                                                      |
| Dubai            | Jebel Ali                      |                                                                                                      |
| Abu Dhabi        | Khalifa Port                   |                                                                                                      |
| Tangier          | Tanger Med                     | Roughly 40 km east of the city.                                                                      |
| New York City    | Port Newark–Elizabeth          | Newark Bay, on the New Jersey side.                                                                  |
| Los Angeles      | San Pedro Bay                  | Covers the adjacent Los Angeles and Long Beach complexes as one destination.                         |
| Houston          | Bayport                        | Roughly 80 km inland along the Houston Ship Channel, whose draft excludes the largest class.         |
| Colón            | Manzanillo                     | Caribbean side of the Panama Canal; see the transit limits below.                                    |

Use one representative harbor marker per roster entry, located at the actual
harbor, and show both city and port names where they differ. Abstract nearby
terminals into that port's facilities rather than separate gameplay destinations.
A roster entry with size-gated berth groups likewise remains one destination with
one marker; its terminals appear inside the port panel, not on the map as rivals.
These mappings represent existing roster entries, not additional ports.

Ports admit ships by size class, which joins the attributes distinguishing ship
classes in section 9. Each port has one or more berth groups, and each group
publishes the largest size class it accepts; a ship that no group at a port
accepts cannot call there at all. Groups keep separate berth counts and queues
under the rules in section 10, so a large ship cannot relieve congestion by taking
a small-ship berth, and a small ship queuing at one group gains nothing from free
capacity at another.

Three launch entries use size gating:

- **Ho Chi Minh City** splits into Saigon, upriver in the city, for smaller
  vessels, and Cai Mep, downstream near the river mouth, for larger ones.
- **Shanghai** splits into the Waigaoqiao river terminals for smaller and mid-size
  vessels and Yangshan, offshore on Xiaoyangshan Island, for the largest.
- **Houston** has a single group whose limit reflects the Houston Ship Channel's
  draft, excluding the largest class from the port entirely.

A split port remains one destination with one map marker. Movement between its
groups belongs to the port's internal facilities rather than being a separate
voyage, and the port panel shows each group's berths and queue.

Waterways carry size limits of their own. The Panama Canal admits every launch
class except the largest, which must route the long way around South America.
Suez admits all launch classes. Colón sits on the Caribbean side of the canal and
is reached from Atlantic ports without transiting it. A pair whose shortcut is a
canal the ship cannot use remains navigable by detour, but those detours are the
longest routes in the world, so section 3's ceiling of 24 real hours for the
slowest ship's longest direct voyage must be validated against them and not only
against canal-assisted routes. Where a detour cannot be brought under the ceiling,
the resolution is that the largest class does not serve that pair; do not raise
the ceiling to accommodate it.

Size classes, each berth group's limit, and each waterway's limit are
configurable.

Each location should have distinct supply and demand. City economic identities,
harbor mappings, trade roles across all 22 goods, and each port's relative
capacity and cost are recorded in [the launch port roster](ports.md). Each port
serves its surrounding region: inland producers supply
export goods, and imports serve inland buyers. Use this regional catchment to
balance the approved roster while keeping economic identities geographically
plausible. Inland flows are part of the simulated economy; the player-facing
initial trading loop remains marine shipping.
These 25 locations are the default launch roster. Propose additions
only when necessary to address an important gameplay balance issue, explaining
the issue and how the addition addresses it. Geographic coverage alone does not
justify an addition. The user has final approval of any additions and the exact
set of ports.

Public information includes ship locations and routes. Selecting another ship
may show its company and ship class, but never its cargo manifest. Owners can
inspect their cargo, quantities, costs, freshness, and trading instructions.
Limit-order instructions remain private. Auction bids are sealed before closing;
after closing, final active amounts are published anonymously as specified in
section 7. Bidder identities remain private. Public market orders show prices
and quantities without identifying their companies.

Ships owned by a company undergoing bankruptcy display a clear public
"Company in bankruptcy" label when inspected. Keep that status visible while
the estate owns the ship, including during voyage completion and liquidation;
remove it when ownership transfers to an active buyer. This does not reveal the
ship's private cargo manifest or trading instructions.

Liquidation lots are an explicit exception: offered cargo's quantity, location,
and freshness become visible to potential buyers. Public ship positions do not
otherwise grant access to cargo data, including through network responses.

Privacy here is a rule about served data, not about what a rival can work out.
The following are public by design: ship positions, routes, and arrival estimates;
whether a ship is in port; berth occupancy and its duration; port congestion; and
anonymous market prints with their prices and quantities. Together these let an
attentive player estimate a rival's cargo, because a long berth stay implies a
large parcel and a sizeable print at a port where one ship is working narrows down
whose it was. That inference is intended play, in the same spirit as real trade
analysis built on public vessel movements, and it is the return on publishing
positions and routes at all.

What must never be served is the manifest itself: the goods and quantities aboard
another company's ship, batch acquisition costs, exact freshness, trading
instructions, limit orders, and sealed bids before closing. No response, feed, or
error message may carry them, and no published aggregate may be constructed so
that one company's holdings can be recovered from it.

Do not blur, quantise, or add noise to the public physical facts in order to
frustrate inference. A ship visibly departs when it departs, so obfuscation is
defeated by simple observation while the map stops telling the truth about the
world. If the resolution of public information ever needs reducing, do it by
publishing less, not by publishing something false: reporting a ship as in port
without separating anchorage from berth would mask handling time behind queue
time without misstating anything.

## 5. Mixed city economy

Simulated city actors provide supply and demand from the beginning and continue
alongside player industry later. Players initially focus on shipping; simulated
households and businesses remain end customers.

- Households consume food, mass consumer products, and luxury goods. Population
  and prosperity shape demand.
- Businesses consume materials and machinery, produce manufactured goods, and
  generate scrap.
- Local producers supply resources, agricultural goods, and manufactured goods
  according to regional geography and industry.

These actors participate in markets and auctions under the same trading rules
as players. Supply replenishes through production and demand through consumption
over time; neither is an unlimited fixed-price trade opportunity. Deliveries can
saturate demand, and purchases can exhaust cheap supply. City views should
explain local production, consumption, and market conditions.

Port specialties overlap: every initial good has several supplying and buying
ports. Differentiate ports through production, demand, operating costs, and
capacity rather than exclusive access to a good. Provide alternative trading
routes when one market becomes crowded, subject to finite supply and demand.

The port roster distinguishes local or hinterland producers from re-export
merchants. Buying demand and selling supply have independent relative weights;
a merchant can do both for the same good. Merchant purchases replenish resale
inventory, not end-consumer demand. Every good retains an actual producer;
counting merchant supply toward port coverage does not make it production.

Re-export merchants buy existing goods through their port's markets, hold them
in paid compatible warehouse space, and resell only available owned stock.
They never generate replacement stock or obtain implicit off-map replenishment.
Goods must arrive through player deliveries or other valid local purchases.
Purchases conserve quantity and preserve batch identity, freshness, and physical
location under the ordinary settlement rules; resale does not count as production.
Starting merchant inventory, if supplied, must be an explicit allocation from
existing producer inventory, not a second copy of goods.

Merchants obey the simulated-actor budget and replenishment rules, reserve funds
and receiving capacity for purchases, and reserve stock for sales. Empty stock,
insufficient funds, or unavailable space prevents new commitments; their
re-export role does not guarantee throughput or exempt them from paid storage.
Ordinary price bands and regional spread limits apply to their order-book quotes.
They cannot trade with themselves or bid on their own consignments.

For luxury goods, merchants buy and sell through scheduled auctions. Purchased
stock may be consigned only to a later auction whose bidding has not opened, once
ownership and available inventory are confirmed. An unawarded bid cannot back a
consignment, and resale follows the same fixed lot, reserve, and storage-coverage
rules as other consignments. Buying and reselling do not consume the goods;
eventual end buyers remain the consumption sink.

Simulated factories require and consume inputs to produce outputs; refineries,
for example, consume crude oil to produce refined fuel. Give these factories
starting input and output inventories so trade can begin immediately. Production
requires available inputs and compatible output storage; starting inventories
do not bypass ongoing resource constraints. Raw-resource producers generate
their goods without requiring imported inputs. Initial production recipes and
inventory quantities remain to be defined and balanced.

Production recipes use the 22 tradable goods where appropriate. Materials
outside that catalogue, such as cask oak, bottling glass or textiles, are
abstracted as local inputs included in production costs rather than added as
tradable goods. This abstraction does not replace required inputs that are in
the trade catalogue.

Production and consumption progress gradually, allowing trade opportunities to
recover over time while heavy trading can saturate a route. Simulated buyers'
budgets replenish over time up to configured caps. Surplus inventory pushes
suppliers' asking prices down; shortages increase buyers' bids within configured
price limits. These responses affect new or amendable orders and do not alter
settled trades or locked auction commitments.

Exact production and consumption rates, budget caps and replenishment rates,
price-response parameters, band widths, the activity decay constant, and dormancy
thresholds remain configurable tuning. The initial goods catalogue is finalized
in section 6, and city economic identities with their per-port trade roles are
assigned in [the launch port roster](ports.md). The later balance between
simulated and player industry remains open.

Computer-controlled producers and buyers do not go bankrupt. They still obey
finite supply, demand, budgets, storage, and berth capacity. When funds or space
are unavailable, they stop placing new orders until resources replenish;
existing commitments remain funded and protected. Bankruptcy rules apply only
to player companies. Budget replenishment is part of the city-economy model
described above, not permission to bypass reservations or physical limits.

### Price level and reference values

Every good has a configured reference value. Simulated buyers' maximum bids and
simulated sellers' minimum asking prices move within a band around it: local
surplus and shortage move prices inside the band, and nothing moves the band
itself. Reference values and band widths are absolute configured constants. They
must never be derived from recent trade history, a moving average, or any other
measure that feeds on its own output, because an anchor computed from past prices
drifts with them and becomes worth manipulating.

Player-to-player order-book trades are not constrained by the band. Arbitrage
against the simulated actors, which remain the ultimate source and sink of every
good, keeps those trades near the band in practice without a rule requiring it.
The same reference values already govern final clearance pricing in section 11.

The band is also the economy's stabilizer. Falling activity thins demand, pushes
prices toward the floor, compresses margins, and retires marginal capacity until
equilibrium returns; rising activity does the reverse. A fixed band bounds both
excursions. Because the price level does not drift, nominal profit stays
comparable across the world's entire history and the leaderboards in section 3
need no inflation adjustment.

### Regional catchments and adjacent ports

Ports sharing a regional catchment in the sense of section 4 draw on
substantially the same hinterland, so their supply and demand move together.
For each good, compute a shared regional reference price from actual regional
inventories and demand, including changes caused by player trading. This is a
variable operating price within the good's fixed global reference band, not a
replacement for the absolute configured anchor. Never derive it from trade-price
history. Recompute it as the underlying inventory and demand state changes.

Simulated port quotes use this shared price plus bounded local adjustments.
Constrain those adjustments jointly so simulated inter-port spreads remain near
the cost of transporting the good between the ports. Validate executable buyer
bids against seller asks across the cluster, rather than only correlating their
midpoints. Numerical transport-cost allowances and response parameters are tuning
choices. Player orders remain unrestricted, and existing settled trades and
locked auction commitments retain their terms. Regional pricing does not move
cargo or pool physical storage: local inventory and receiving capacity still
limit executable quantities.

Three launch clusters need this: Hong Kong, Shenzhen and Guangzhou in the Pearl
River Delta; Rotterdam, Antwerp and Hamburg in northern Europe; and Dubai with
Abu Dhabi. Independent price generation at ports 30 to 130 km apart would sustain
a spread that real markets that close have long since arbitraged away, and it
would be the least risky profit in the game: negligible transit, no weather
exposure, no spoilage window. Because ROI rewards turnover in proportion to cycle
count, such a spread would make a short intra-cluster loop the dominant ROI
strategy and leave long-haul trading competitive only on absolute profit.

Shared regional pricing does not make clustered ports interchangeable. They
still differ in berth capacity and handling speed, storage cost, size gating,
and which goods they specialize in, so a cluster behaves as one market reached
through several gateways with different physical characteristics. Real traffic
inside such a cluster is mostly feeder movement earning carriage rates rather
than arbitrage on price, and the initial trading loop has no carriage-for-hire
mechanic to express it, as noted in section 14. The explicit bounds on simulated
quote spreads prevent persistent system-funded intra-cluster arbitrage;
correlation alone does not guarantee it.

Cluster membership is recorded in [the launch port roster](ports.md), which
also states how ports inside each cluster are differentiated. Regional
inventory and demand responses and the bounded local price adjustments are
tuning choices. Validate them under sustained player-driven
inventory depletion as well as ordinary production and consumption.

### Activity index and market depth

The world scales market depth to current participation, never the price level and
never a cumulative count of accounts ever created.

Each company carries an activity weight that decays exponentially with the time
since its last qualifying action, capped at 1. A qualifying action is an economic
one with real substance, such as a settled trade, a voyage dispatch, a lease
acquisition, or an accepted bid, above a configured minimum value. Signing in is
not a qualifying action, and negligible trades must not sustain a weight. The
world activity index is the sum of these weights, decaying on wall-clock time
as a player timer under section 3. The decay constant is configurable,
provisionally about one real week, so a company continuing
substantial economic activity stays near full weight while one without qualifying
actions falls close to zero within a month. Automated trades and dispatches count
for this economic measure. Owner absence is tracked separately for dormancy;
signing in resets absence but does not itself increase economic activity weight.

Simulated buyer budget replenishment rates and producer output rates scale with
the world activity index. Budget caps stay a small multiple of the replenishment
rate, provisionally one to two game quarters' worth, so unspent budget cannot
accumulate into an overhang that later floods a market.

Two constraints on the metric are deliberate:

- **Cap each company's weight at 1 and do not weight it by fleet size.** The index
  measures presence, not intensity. Scaling demand by capacity would be positive
  feedback: more ships producing more demand producing more ships. Scaling by
  participant count instead means additional tonnage dilutes margins, which caps
  fleet growth and is what gives ROI its meaning.
- **Scale globally rather than per port.** Regional scaling is directly
  manipulable by keeping a few companies minimally active in one area to inflate
  local demand. A global index dilutes that effort to nothing.

### Dormant companies

A company becomes eligible for dormant closure after its owner has been absent
for a configured interval. Track the owner's last authenticated visit, including
visits within an existing signed-in session; unattended session refreshes and
automated company actions do not reset absence. A returning owner resets the
absence timer without needing to trade. Economic activity weight is not the
dormancy test, so profitable automated routes cannot prevent closure indefinitely.

Give advance notice of the closure deadline and how to prevent closure, with a
configured warning period before liquidation. An authenticated return before
closure cancels the pending dormant closure and its warnings. Absence and warning
timers are player timers under section 3: they run on wall-clock time and do
not pause with the world, because absence is a fact about the real world rather
than an in-world process. Their durations are tuning parameters; closure must
not occur without the advance warning period having elapsed.

Warnings reach a linked identity out of band. An unlinked account can be warned
only in app, where an authenticated visit would reset absence anyway, so its
warning period is effectively inert; section 2 requires that consequence be
stated to the player when they decline to link. An unreachable warning is not a
reason to defer closure. The warning period is a duty to attempt notice, not a
guarantee it was read, and unlinked accounts are among the likeliest to have been
abandoned outright.

At closure, liquidate through the bankruptcy estate rules in section 12,
including cancellation of automation and removal of residual cash from
circulation. Dormant closure does not increment the lifetime bankruptcy count
and is recorded separately. It removes the company from the economic activity
index. Ordinary operating costs and bankruptcy rules continue to apply during
owner absence. Returning after closure does not restore the liquidated estate.

### Money supply

Accounting profit and player cash stock are separate measures. Profit follows
the recognition rules in section 13. Player cash stock includes all cash held by
player companies, including reserved cash, and changes only when cash crosses
the boundary between those companies and the simulated economy. Moving cash
into or out of a reservation does not change the stock.

Cash sources include cash starter grants, loan disbursements, payments from
simulated buyers, and shipyard buybacks. Cash sinks include purchases from
simulated sellers, operating payments to simulated actors, loan principal and
interest repayments, and estate cash removal. Ordinary player-to-player payments
net to zero across companies. Bankruptcy auction payments follow their explicit
rule: they leave the player economy instead of being credited to the seller.
Record each actual cash flow once; do not count estate proceeds that were never
credited to a company as another cash removal.

Buying a ship removes cash without an immediate operating loss. Depreciation
reduces profit without removing cash, and loan disbursements add cash without
profit. Starter ships likewise add assets without creating cash. A profitable
player base can maintain a static cash stock by reinvesting its earnings.
Treat cash stock as an observable, not a target, and instrument sources and sinks
separately from accounting profit.

Ship replacement is the terminal sink among those operating payments: profit is
reinvested in tonnage, that payment leaves the player economy, and the escalating
maintenance and scrapping rules in sections 9 and 10 ensure the tonnage itself
eventually leaves the world rather than accumulating. Maintenance payments are
cash sinks as well as operating expenses, and they grow as the fleet ages.
Depreciation schedules influence replacement decisions and book-value-based
buyback payments, but depreciation itself moves no cash.

Instrument the money stock per active company and the traded price level against
reference values, and treat sustained divergence as a signal to retune flows. Do
not attempt to steer the money stock directly.

## 6. Cargo categories

| Category                     | Default market                                | Typical strategy                | Main gameplay distinction                                                                                   |
|------------------------------|-----------------------------------------------|---------------------------------|-------------------------------------------------------------------------------------------------------------|
| Bulk commodities             | Continuous limit order book                   | Repeatable high-volume routes   | Thin margins reward efficient transport and full holds; later feed industry.                                |
| Luxury items                 | Periodic auctions for specific lots           | Opportunistic shipments         | High value in little space, shallow demand, and competition for scarce lots.                                |
| Industrial machinery         | Procurement auctions for requested deliveries | Contract-driven voyages         | Large, irregular commitments of capital and capacity, with delivery deadlines; later supports construction. |
| Mass consumer products       | Continuous limit order book                   | Recurring distribution routes   | Broad recurring demand and saturation from rival deliveries, across a wide range of value density.          |
| Scrap                        | Continuous limit order book                   | Conditional return cargo        | Recovered material flowing from consuming cities back toward industry makes round trips viable.             |
| Perishables, such as bananas | Limit order book with freshness grades        | Time-sensitive recurring routes | Shelf life, transit, congestion, storage, and demand determine whether a shipment remains profitable.       |

Market styles are defaults, not permanent prohibitions on other mechanisms.
Units, lot sizes, grades, and detailed market eligibility remain open.

The finalized launch catalogue has 22 goods: six bulk commodities, four mass
consumer products, and three in each other category. Tankers and liquid storage
are included at launch.

| Category               | Launch goods                                             |
|------------------------|----------------------------------------------------------|
| Bulk commodities       | Iron ore, grain, lumber, crude oil, refined fuel, vegetable oil  |
| Luxury items           | Whisky, jewelry, designer clothing                       |
| Industrial machinery   | Turbines, construction equipment, agricultural machinery |
| Mass consumer products | Electronics, appliances, everyday clothing, spices       |
| Scrap                  | Scrap aluminium, copper scrap, recovered plastics        |
| Perishables            | Fruit, seafood, meat                                     |

Lumber means sawn lumber, not raw logs or finished furniture. It trades on the
continuous limit order book against steady simulated construction and
manufacturing demand, supporting repeatable routes. It uses ordinary dry holds
and ordinary storage, with no refrigeration or perishable aging. Tune its cargo
density so representative dry ships fill their holds before reaching their weight
limit, in contrast to iron ore and grain. Its modest value per unit of volume
makes warehouse rent and prompt onward shipment important to profitability;
retain enough dependable demand to distinguish it from opportunistic scrap
backhaul. Exact density, reference value, and lot sizes remain tuning parameters.
Later player-owned sawmills can produce lumber using the shared industry rules;
raw timber is an abstract local input until a separate tradable good is approved.

Mass consumer products span a wide value density too. Everyday clothing and
appliances fill volume at moderate margins on recurring routes. Spices sit at
the opposite end: a hold of cardamom or saffron is worth a fortune in very
little space, and unlike luxury goods they trade on a continuous order book
against broad, replenishing demand rather than in periodic auctions for scarce
lots. That combination is deliberate, because it is the only high-value-density
trade a small ship can work without waiting on an auction cycle. Spices are not
perishable for game purposes: real ones lose potency over a year or two, but
modelling that would collapse them into the perishables archetype and remove the
distinction that earns them a place.

The four spice origins are the historic ones — Indian, Ceylon, Indonesian and
Vietnamese production — which the launch roster already covers, with Dubai as a
re-export hub. Keep spice density and reference value far enough above the other
consumer goods that the contrast survives balancing.

Scrap spans a wide value density, and that spread is the category's point rather
than an inconsistency. Recovered plastics are bulky and cheap, so they fill volume
and only pay when a hold would otherwise travel empty. Copper scrap is among the
densest-value non-precious cargoes and behaves like a bulk commodity, filling
weight and justifying a voyage on its own. Scrap aluminium sits between them.
Tune each good's density and reference value to preserve that contrast, since it
is what exercises the weight-versus-volume tradeoff in section 9; do not flatten
the category into uniformly cheap, bulky freight.

Simulated refineries buy crude oil and produce refined fuel for sale; other
cities consume refined fuel. These actors follow the shared production, budget,
capacity, and market rules. Distinct crude and refined-fuel supply and demand
create additional tanker routes and potential return cargo.

Three goods need liquid capacity: crude oil, refined fuel and vegetable oil. A
tanker carries one at a time, and switching incurs automatic cleaning time and
cost shown in the handling estimate. Cleaning between crude and refined fuel is
the cheap switch; preparing a tank that held either for food-grade vegetable oil
costs substantially more, which is why dedicated vegetable-oil tonnage exists.
All three use separate liquid-storage allocations and must never be mixed.

Vegetable oil exists to give tankers a counter-flow. Palm, coconut and soy oil
move from tropical producers toward the same industrial and populous regions
that buy refined fuel, so a tanker can discharge fuel and load oil for the
return leg. That does not make every leg loaded: a tanker delivering fuel to a
port that exports no liquid sails back in ballast, which is both realistic and
intended. Ballast legs are why the oil trader starter package includes a general
freighter, and they are not a defect to be fixed by relaxing the liquid-hold
rule.

The launch roster must retain at least one two- or three-port liquid trading
cycle containing vegetable oil and either crude oil or refined fuel. Two-port
routes exchange vegetable oil for either petroleum cargo. Triangles may, for
example, carry crude oil from A to B, refined fuel from B to C, and vegetable oil
from C back to A. Validate a seller and buyer of the same cargo on each leg and
require distinct ports before returning to the origin; one dual-role port cannot
satisfy the cycle by itself. Existing cleaning requirements apply at each cargo
switch. This is a roster coverage check, not a restriction on player route length
or a guarantee of available stock, capacity, or profitable prices on every voyage.

Perishable batches retain harvest time and remaining shelf life through resale.
Freshness declines in transit and storage; older goods become less valuable.
Expired goods cannot sell as food and are discarded. Refrigeration slows aging
at additional cost and with ship-capacity tradeoffs. Ordinary holds can carry
perishables without slowing spoilage. Buyers can require a minimum remaining
shelf life as well as a maximum price. Freshness grades use shared percentage
bands of shelf life remaining across perishables. Always show estimated real
time remaining under current storage conditions as well; buyers can specify a
minimum remaining lifetime appropriate to their planned voyage. Refrigeration
changes aging speed rather than resetting batch age. Exact grade thresholds,
aging rates, and shelf lives remain tuning decisions.

Some launch perishables are effectively refrigerated-only. Seafood and meat cannot
credibly hold a usable shelf life in an unrefrigerated hold across even a short
voyage, so their unrefrigerated shelf lives must be short enough to be plausible,
which makes ordinary holds impractical for them in nearly every case. That is
intended, and it is what gives refrigerated capacity and the fresh produce starter
package a purpose. Treat it as a constraint on tuning rather than a free choice,
and do not read "ordinary holds can carry perishables" as a promise that every
perishable travels viably unrefrigerated. Fruit is the launch perishable expected
to tolerate ordinary holds on shorter routes. Because real fruit shelf lives span
orders of magnitude, tune the good against a single reference case rather than an
average, and anchor its shelf life and aging rate on bananas, the trade that
created refrigerated shipping.

## 7. Markets, remote trading, and reservations

A shared exchange interface exposes separate local markets at each port.
Players have free worldwide access to current prices, order-book depth, recent
trades, and auction listings. Destination prices are current information, not
guaranteed future proceeds. Market depth must reveal how much can trade at a
price rather than imply unlimited liquidity at the headline quote.

Players can buy and sell remotely from the start. Purchased goods remain at the
purchase port in the buyer's leased warehouse; transportation is still needed.
Remote sales require owned goods already at that port. Cargo aboard a ship can
only sell when the ship has a berth and can unload; anchorage does not bypass
port handling. Warehouse cargo can change ownership without a ship present.

Standing buy orders reserve cash and appropriate warehouse capacity. Standing
sell orders reserve owned goods. Cargo auction bids also reserve cash and space.
Orders and bids cannot collectively spend the same money, sell the same goods,
or exceed capacity. Direct purchases loaded aboard a berthed ship reserve hold
capacity instead. Renting additional space is subject to port availability.

Limit orders permit partial fills and apply their price limit to each unit's
execution price. Large orders can consume several price levels but cannot trade
beyond their limit. Order books match by price, then time: execute the best
compatible price first, with earlier server-accepted orders taking priority at
the same price. Incoming orders trade at the resting order's price, never
outside either party's limit. For example, a buy limit of $100 matches a resting
$90 sell offer at $90. If a fill spans price levels, each portion uses its
resting price. Eligibility still requires compatible goods, freshness, funds,
and receiving capacity.

Reducing an order's remaining quantity preserves its time priority and releases
excess reservations. Increasing quantity, changing price, or changing eligibility
terms such as minimum freshness resets priority for the entire remaining order
to its new server acceptance time. An unchanged resubmission preserves priority.
Amendments affect only unfilled quantities, never completed trades. Update
reservations with the amendment; if the replacement cannot be funded or supported
by cargo/capacity, reject it and preserve the existing order and reservations.
Automatic amendments to linked remote orders follow these same priority rules.
Standing limit orders default to remaining active until cancelled, with an
optional player-set expiration. At expiration, cancel only the unfilled
remainder and release its reservations; completed trades stand. Orders can end
earlier under existing rules for invalid backing, storage expiry, spoiled cargo,
bankruptcy, or linked-stop cancellation/handover. Optional expiry never extends
a supporting lease or freshness guarantee. An expired linked order does not
cancel its collection stop or undo goods already purchased for it. Expiry edits
that leave price, quantity, and eligibility unchanged preserve time priority.

Perishable sell orders support optional automatic markdowns: players may set
minimum sale prices for successive freshness grades. Apply only the player's
configured prices as the backing cargo ages; never invent a lower price. With
markdowns disabled, retain the existing minimum and expose the cargo's actual
current grade, matching only buyers whose freshness requirements it satisfies.
Automatic price or grade/eligibility changes reset time priority under the normal
amendment rules. Cargo expiry removes the expired backing and releases its
reservations; it does not create a sale. Require a percentage for every freshness
grade when saving a markdown preset; reject incomplete schedules. Automatically
split mixed-grade backing into separately priced portions, each using its actual
grade and the applied schedule. Preserve total owned/reserved quantities without
duplicating stock. Portions whose price or eligibility changes receive new time
priority; unchanged portions retain theirs. These rules apply to standing sell
orders, not locked auction reserves.

Markdown schedules can be saved as reusable player presets and applied to
selected sell orders or automated sell instructions. Applying a preset copies
its settings into that order or instruction. Editing or deleting the saved
preset does not silently alter existing applied settings; the player must
explicitly apply an update. Accepted updates to active orders follow normal
price/eligibility amendment and priority rules. Automated instructions create
orders using their own applied settings, not a changing live preset reference.
Preset use remains optional and does not create a company-wide markdown policy.
Presets express grade prices as percentages of an order's initial asking price,
not percentages of live market prices or of each previous markdown. For example,
100%, 80%, and 50% against an initial $100 price yield $100, $80, and $50.
An optional absolute floor prevents any scheduled markdown from lowering the
minimum below that amount: effective minimum is the greater of the grade's
calculated price and the floor. Record the initial asking-price basis when the
order is created and retain it through automatic grade changes. Automated sell
instructions supply that initial price for each order they create. Keep the
original asking-price basis unless the player explicitly changes it. An explicit
rebase recalculates unfilled portions using their applied percentages and floor;
normal amendment priority rules apply and completed trades remain unchanged.
Currency rounding remains an implementation detail.

There are no exchange fees initially, including order-book trades, auction
sales, procurement awards, order placement, amendments, and cancellations.
Do not deduct an exchange commission from proceeds. Port handling, storage,
fuel, and other established logistics costs remain separate expenses. Auction
rules are specified separately below.

### Trade settlement and physical handling

For order-book trades involving a ship, settle before handling, once the ship
has a berth and can begin loading or unloading. Match against the market then
available, respecting price limits and permitting partial fills. Payment and
ownership transfer immediately for the matched quantity; subsequent price
changes do not alter the trade. Queue arrival does not lock a price.

The committed cargo is marked **in handling** until physical transfer finishes.
Its owner and physical location remain separately tracked. Reserve destination
capacity and retain occupied source capacity until goods actually leave it;
ownership transfer alone does not free physical space. Committed cargo cannot
be sold again or redirected during handling, and the ship cannot depart or be
rerouted before its committed handling completes. Freshness continues declining
after ownership changes. Check contractual freshness requirements at settlement;
show projected freshness after handling before commitment as an estimate, not a
guarantee. The buyer bears subsequent deterioration and spoilage during handling.
Expired cargo is discarded and recorded as the current owner's loss; do not
reverse the trade, refund the price, or reclaim a supplier's returned deposit.
For transfers of a company's own stock, that company continues bearing the loss.
Handling completion does not settle the trade a second time.

Show estimated freshness both at arrival and after unloading, including expected
queue and handling time. Update these projections when delays or plans change;
they remain estimates rather than guarantees. Refrigeration slows aging but
never restores freshness already lost.

Transfers between storage types take handling time and require compatible
receiving capacity. Interrupted handling resumes from saved progress, preserving
ownership and the appropriate source occupancy and destination reservations.
Do not repeat completed movement or settlement. Freshness follows the cargo's
actual storage conditions; world-wide outage time follows the separate world-clock
policy.

For example, a ship instructed to buy up to 100 tonnes of fruit at no more than
$80 per tonne buys only 60 tonnes if that is all the market offers within its
limit when berthed. Payment and ownership transfer for those 60 tonnes, hold
capacity is reserved, and loading begins. The ship follows its departure
instructions after loading finishes. Unfilled buy quantities follow the player's
wait or expiry instructions; unsold cargo follows retain or warehouse
instructions.

Each port has a shared storage pool for each storage type. Remote warehouse
trades settle immediately when matched, provided the buyer already has sufficient
free compatible leased capacity. Transfer ownership and allocation atomically:
consume the buyer's free allocation and free the seller's occupied allocation.
The goods stay physically in the same pool, with unchanged total physical
occupancy and freshness. No transfer handling time, handling fee, or berth is
required for this same-pool transaction. Selling goods does not terminate the
seller's lease or release their leased capacity for other tenants to rent.

Auction cargo settlement uses the same allocation transfer. This does not allow
a buyer to bypass their own capacity requirement by assuming the seller's lease.
Transfers between storage types or between ship and warehouse remain physical
handling operations and are not covered by this instant-transfer rule. Auction
and procurement settlement follow the separate rules below.

### Auction settlement

All auctions are computer-run. Players sell luxury goods by consigning lots to
scheduled port auctions, rather than starting individual auctions on demand.
Players choose their lot and minimum sale price; the system controls the
schedule, bidding, and settlement. Simulated buyers and other players may bid.
Where the roster specifies buying demand for that good at that port, including
re-export merchant demand, simulated bidders must provide auction competition.
Sealed second-price bidding pays the reserve whenever only one eligible bidder
appears, so at launch population, with one auction per port per day, a player's
consignment would otherwise realize exactly its minimum and the competition for
scarce lots that distinguishes luxury goods in section 6 would never occur. Give
simulated buyers private valuations drawn around the good's configured reference
value and adjusted for local demand, and have a configured expected number
participate per lot, so a consignment faces real competition without a
guaranteed clearing price. Simulated bidders obey the same budget, capacity, and
eligibility rules as players. Valuation spread and expected participation are
tuning parameters; participation where buying demand exists remains subject to
those resource constraints and does not guarantee a bid or sale.

Where the roster specifies no buying demand, including export-only and not-traded
roles, luxury consignments are still permitted but auctions rely entirely on
player bids. Show **No simulated buyers** before the seller commits a consignment
and on its auction listing. A not-traded role restricts simulated actors, not
player-to-player trading. Apply the ordinary reserve and settlement rules; an
unsold lot returns to available inventory under the existing release rules.
Each lot settles separately under the asset-auction rules below. Consigned cargo
stays reserved in the seller's warehouse until sold or released; scheduling does
not bypass finite storage or lease coverage.

Before bidding opens, sellers may revise the lot, change its reserve price, or
withdraw the consignment. Accepted changes update cargo reservations and must
remain backed by available goods and storage coverage. When bidding opens, lock
the lot, reserve price, and cargo commitment through closing; sellers can no
longer revise or withdraw it. Bidder revision and withdrawal rights remain
unchanged. If the lot does not sell, release its auction reservation and return
it to available inventory in the seller's warehouse, subject to ordinary lease
and freshness rules. Relisting requires a new consignment; it is not automatic.
System exceptions such as spoilage or bankruptcy follow their separate rules.
Luxury consignment auctions initially run once every 24 real hours at each port.
Keep frequency configurable so auctions can become more frequent as the player
population grows; do not hard-code a daily assumption into scheduling or the UI.
The bidding window length is configured independently of the interval between
auctions. Both begin at 24 real hours, but raising frequency must never shorten
the window: a window has to span several check-ins regardless of how large the
player population grows, and deriving it from the interval would trade that
property away exactly when more players make it matter most. Where the window
exceeds the interval a port runs several auctions concurrently, each with its own
published opening and closing time.

Concurrency splits liquidity, because bids reserve funds and a bidder cannot back
the same cash in several simultaneous auctions. Keep the interval long enough that
only a few windows overlap, and prefer batching lots of the same good into a
single auction event so competition concentrates rather than spreading thinly
across near-identical listings.

A consignment joins the earliest scheduled auction whose bidding has not yet
opened; submissions at or after an auction's opening enter a later one.
Assignment is system-controlled rather than chosen by the seller. Sellers can
prepare consignments for future windows while current bidding is underway. Give
ports fixed, staggered schedule offsets so auctions close at different times
throughout the day. Show opening and closing times in the player's local time
with countdowns. Local display time does not alter the authoritative schedule.
The interval, the window length, and exact port offsets all belong to the
configurable schedule. Schedule changes must preserve the published opening and
closing times of already-scheduled auctions and their reservations, applying to
future schedules. Procurement requests and bankrupt assets also join the next
unopened scheduled port auction once ready, using that port's opening, closing,
and bidding window. Procurement delivery windows follow award and must leave
time to source and transport goods. They are distinct from the bidding window.
Assets still at sea or in handling remain ineligible until their existing
readiness conditions hold.

Perishable liquidation lots use fixed, expedited two-real-hour bidding windows,
configurable for future auctions. If a lot cannot remain usable through the
expedited closing time under current storage conditions, bypass the auction and
proceed directly to clearance while usable, or disposal if expired. This schedule
exception applies to perishables in both lease and bankruptcy liquidation and
does not extend existing storage or reset freshness.

Procurement requests are system-originated only in the initial game. Players bid
to supply computer-controlled buyers; they cannot post delivery requests.
Bankruptcy liquidations are also organized by the computer. This supersedes the
earlier player-buyer procurement bankruptcy rules, which are outside initial
scope.

Auctions support advance maximum bids, and procurement bidding supports a minimum
acceptable contract payment. Participation windows should accommodate several
check-ins rather than reward being online in the closing seconds.

Existing-asset auctions cover luxury cargo lots, bankrupt companies' ships and
cargo, and later facilities:

- Bids reserve funds. Cargo bids also reserve compatible warehouse capacity at
  the lot's port through auction closing. Reject a bid whose supporting lease
  expires before closing unless the player first extends it. A won lot whose lease
  then expires receives the post-settlement grace period in section 11.
- At closing, the winner automatically pays the auction clearing price and
  receives ownership. Release losing bidders' reservations and any unused
  winning cash reservation; winning cargo reservations become occupied storage.
- Assets stay where they are. Cargo enters the winner's storage allocation at
  that port, ships become controllable where docked, and facilities stay in their
  city. Same-pool storage transfers use the allocation rules above.
- Only available assets can be offered. Cargo must be ashore and free of other
  commitments; ships must have completed their voyage and handling. Offered
  assets cannot acquire conflicting commitments before closing.
- Perishable lots keep aging and show projected freshness at closing. If a lot
  expires before closing, cancel its auction and release bid reservations.

Existing-asset auctions use sealed second-price bids. Bid amounts remain hidden
during bidding. The highest eligible bid wins, provided it meets the published
reserve price, and pays the greater of the reserve price and the second-highest
eligible bid. With only one eligible bidder, the winner pays the reserve price.
Reserve each bidder's full offer until the applicable release point; after
settlement, release the winner's excess cash reservation. There is no automatic
proxy bidding or incremental public price competition.

Procurement uses the reverse equivalent: sealed second-price offers. The lowest
qualifying offer at or below the buyer's published maximum wins. Its contract
payment is the second-lowest qualifying offer, capped by that maximum; with only
one qualifying supplier, the payment is the published maximum. Offers remain
hidden during bidding. The payment is fixed at award and paid only on qualifying
delivery. Release the buyer's cash reservation above the awarded payment.

For example, offers of $80,000, $90,000, and $110,000 against a $100,000 maximum
award the contract to the $80,000 supplier for $90,000. Each supplier reserves
$10,000 while bidding (10% of the buyer's $100,000 published maximum). At award,
the winner retains a $9,000 deposit (10% of the $90,000 awarded payment) and
recovers the $1,000 excess; unsuccessful bidders recover their full deposits.

In both auction types, equal winning amounts are resolved in favor of the
earliest accepted bid at that amount. Use server acceptance order, not client
timestamps. A tied competing bid still counts when setting the second price:
the winner pays or receives the tied amount.

Bidders may freely revise or withdraw sealed bids until closing in both auction
types. Each company has one active bid per auction; revisions replace that bid
rather than create additional bids that could influence the second price.
Changing the amount gives the bid a new server acceptance priority. Resubmitting
an unchanged active bid preserves priority; withdrawing and re-entering starts
fresh. Withdrawn and superseded bids do not affect winner selection or price.

Accepted revisions update the associated cash, deposit, and capacity reservations
without double allocation. Reject a revision that cannot be backed by the
required resources, preserving the previous accepted bid and its reservations.
Withdrawals release bid reservations, not the underlying warehouse lease. Only
changes accepted by the server before closing affect the result; after closing,
asset settlement and awarded-contract obligations apply. This permission covers
bidders, not an auction organizer cancelling the auction.

Ordinary sale proceeds go to the seller; bankruptcy auction payments leave the
economy as specified in section 12.

After closing, both auction types publish the outcome, final sale or awarded
contract price, and an anonymous list of final active bid amounts. Preserve
separate entries for equal amounts, but expose no company names or persistent
bidder identifiers. Withdrawn and superseded bids are not part of the list.
Procurement award is distinguished from later delivery and payment. Each
participant privately sees their own bid, outcome, payment obligations, and
released reservations. Bids remain sealed before closing.

Both asset and procurement auctions close at their published fixed time. Late
bids, revisions, or withdrawals never extend closing. Only changes accepted by
the server strictly before that time participate; commands accepted at or after
closing are rejected. Storage reservations use that fixed close for coverage.
Server downtime and recovery follow the world-clock policy in section 3: a
game-wide outage pauses auction schedules and closing times together with every
other simulation clock, and resumes without catch-up.

Companies cannot bid on their own consignments; the existing prohibition on
bidding on a previous company's liquidation also applies. Coordinated bidding
intended to manipulate prices is prohibited. Enforcement and broader multi-account
controls remain in the abuse-controls decision group.

Any active company with the required reserved deposit may bid for procurement;
it need not already own the goods or a suitable ship. It remains responsible for
sourcing and delivering the entire qualifying shipment on time.

Cargo and supporting storage must still be valid at auction close. Goods
expiring exactly at closing cannot sell; storage leases ending exactly at
closing require renewal to support a purchase, since the capacity must exist
when the lot settles. Such invalid backing cannot participate in price setting
or settlement. Procurement delivery deadlines are inclusive: a complete
qualifying shipment at a berth that can begin unloading at or before the
deadline satisfies it. Arrival in the port or queue alone does not. These
product rules must govern event ordering even when the timestamps coincide.

Procurement auctions create future delivery contracts rather than transferring
payment or cargo ownership at auction close:

1. The buyer reserves the maximum contract payment and compatible receiving
   capacity for the full shipment when posting the auction.
2. Suppliers bid the payment required to deliver the specified quantity and
   quality to the destination by a stated deadline. Bids are backed by reserved
   performance deposits; unsuccessful bidders recover their deposits.
3. Award commits the winning supplier's deposit and creates the contract. The
   buyer's contract payment remains reserved until delivery or failure.
4. Initial contracts require one complete qualifying delivery, with no partial
   settlement. The deadline is measured when the ship has a berth and can begin
   unloading; merely reaching the port or queue does not satisfy it.
5. On qualifying delivery, transfer payment and cargo ownership before unloading
   and immediately return the supplier's deposit. Apply the normal rules for
   committed handling; receiving reservations become occupied storage as unloading
   proceeds. Congestion forms part of the supplier's delivery risk.
6. On supplier delivery failure, release the buyer's reserved payment and
   receiving capacity, and pay the forfeited deposit to the buyer as compensation.
   Unsold cargo remains the supplier's property.

### Procurement deposits and receiving capacity

While bidding, reserve a performance deposit of **10% of the buyer's published
maximum payment**, independently of the supplier's offer. At award, reduce the
winner's retained deposit to **10% of the actual awarded contract payment** and
release any excess; release unsuccessful bidders' deposits in full. Retain the
winner's deposit until successful settlement or contract failure. Keep the 10%
rate configurable for future auctions while preserving published terms. This
supersedes the earlier supplier-bid-based deposit, preventing a very low offer
from securing a large contract with a negligible deposit. Returning a
deposit on success is separate from paying the contract price. Players cannot
create artificial procurement requests for accomplices; collusion in bidding and
other value transfers still needs safeguards.

A supplier can replace unsuitable cargo and try again within the delivery
window. An unsuccessful attempt is not itself default. Missing the deadline
without a complete qualifying delivery, or withdrawing after award, forfeits
the deposit. There is no free cancellation by either party after award; buyers
cannot remove committed cash or receiving capacity.

At posting, the buyer must secure compatible leased capacity for the entire
shipment, with coverage from the earliest permitted delivery through the
deadline plus an unloading allowance. Show the required coverage before posting.
The reservation is unavailable to other purchases while the auction or contract
is active. Release it if no acceptable bid is awarded or the contract fails;
on success, retain the commitment through physical unloading and convert it to
occupied storage as goods arrive. Releasing a reservation does not terminate
the underlying warehouse lease or refund rent.

Simulated city buyers must also reserve receiving capacity and obey storage and
congestion constraints. They cannot accept unlimited deliveries outside the
port's physical limits.

Procurement buyers are computer-controlled and cannot go bankrupt. Their reserved
payment and receiving capacity are a firm delivery guarantee. Before posting,
validate receiving coverage through the delivery window plus estimated unloading
time. If a later estimate or actual handling requires longer, preserve the space
and charge the computer buyer under protected completion; a buyer-side funding
or storage problem cannot default an otherwise valid supplier delivery.

If a system fault prevents acceptance, preserve the supplier's committed cargo
and deposit, suspend the affected contract deadline, and retry acceptance after
recovery. Protect the affected cargo from loss of eligibility through aging
caused by that acceptance fault; normal voyage and queue aging still apply.
Do not cancel the contract or pay/refund it twice. Supplier-caused lateness is
not excused by this rule, and an unrelated later fault does not revive an already
defaulted contract. This targeted protection is separate from the world-wide
outage policy in section 3. Player-buyer contract cancellation and bankruptcy
compensation are not initial-game mechanics.

Supplier bankruptcy immediately defaults every awarded delivery contract that
has not yet settled, including shipments already underway. Pay each reserved
performance deposit to its buyer and release that buyer's reserved payment and
receiving capacity. Undelivered cargo remains with the bankrupt company for
liquidation; its ships follow the normal voyage-completion rules. Contracts
already settled at a berth are completed sales: finish their committed unloading
without defaulting them or settling them again.

Freshness requirements are checked at settlement; subsequent handling
deterioration is the buyer's responsibility. Before settlement, check estimated
unloading duration against reserved lease coverage. Use protected completion for
overruns: once delivery settles, receiving space stays reserved until unloading
finishes even if the lease expires. The buyer pays an overrun rate disclosed in
advance. Protected space continues to count against the port's physical capacity
and cannot be rented to another party; lease timing alone must not strand the
supplier or pause committed unloading.

The unloading allowance calculation and disclosed overrun rate are tuning
parameters. The computer buyer funds overruns and retains receiving space even
if the pre-settlement estimate exceeds the original coverage. Scheduling must
not promise that protected space simultaneously to another tenant. New leases
start immediately; only renewals book a subsequent term in advance, as specified
in section 11.

## 8. Ship instructions and repeatable routes

Players can give each destination instructions to sell up to a quantity above a
minimum price, buy up to a quantity below a maximum price with a spending cap,
then wait or continue. Sell instructions run before buy instructions. Unfilled
instructions stay active while the ship waits for its configured cargo targets,
subject to their explicit expiry and the stop's optional maximum wait.

A ship instruction is distinct from a standing exchange order. Instructions
become executable when the ship has a berth and can load or unload, not when it
first reaches the port or joins its queue. They must respect current funds,
cargo, capacity, and existing reservations.

Arrival plans may sell qualifying cargo, unload unsold goods into reserved
warehouse space with an active sell order, or retain unsold goods aboard.
Without sufficient reserved storage, excess cargo stays aboard.

Port calls complete planned unloading before beginning purchases and loading.
Settle qualifying sales when unloading can begin, then physically unload sold
cargo and any owned cargo assigned to available warehouse space. Sale proceeds
are available at settlement, but occupied hold capacity is not freed merely by
selling. Once the unloading phase completes, calculate actual free weight and
volume, allocate qualifying owned stock, then buy and load the shortfall.
Purchase prices are those available at this later phase; do not lock them at
initial berth entry against space that unloading is expected to free. Cargo
retained aboard continues to count toward capacity and applicable load targets.
Earmarked purchase budgets remain strict despite newly received sale proceeds.

Loading instructions use owned warehouse stock first, then buy any remaining
shortfall from the local market within the player's price and spending limits.
A target such as "load up to 100 tonnes" includes qualifying cargo already
aboard; it is not an instruction to add another 100 tonnes on every visit.
Only compatible goods meeting the instruction's freshness requirements qualify.
Stock reserved for another ship, sale, auction, or handling operation is not
available. Loading remains subject to actual free ship weight and volume, and
requires a berth and handling time. Transferring owned goods does not create a
trade or reset their purchase cost or freshness.

By default, ships claim available owned stock when berthed. Players may instead
reserve specific available warehouse stock in advance for a particular ship's
collection at that port. Reserved goods remain in the warehouse, count against
its capacity, continue aging, and cannot also be sold or allocated to another
ship. At loading, use the ship's qualifying reserved stock first, then other
available owned stock, then buy any shortfall within limits. Advance stock
reservation does not lock market prices, reserve unowned goods, or guarantee
freshness at arrival. Automatically release the associated advance stock
reservation when its collection stop is removed or cancelled, including a reroute
that removes that stop. A delay or course change retaining the same collection
stop keeps the reservation. Released cargo remains owned in the same warehouse
and becomes available for other uses; no sale, movement, or lease cancellation
occurs. Already-committed handling cannot be cancelled through this mechanism.
When reserved perishables cease to meet the collection instruction's minimum
freshness, release the affected collection reservation and replace it from other
qualifying, unreserved owned stock at the same port, using earliest expiry first.
Notify the player of any remaining shortfall. Released goods remain owned and
available for sale until expiry; expired goods are discarded and their occupied
capacity released. This replacement does not create or enlarge market purchases
or spend additional cash. Existing linked orders retain their current authorized
unfilled demand; do not replenish their completed quantities merely because
those goods aged. Any remaining collection shortfall is reconsidered at berth
under the normal loading rules.

Advance collection reservations survive lease expiry through the 12-real-hour
grace period, allowing the assigned ship to collect its planned goods. They do
not extend grace or postpone liquidation. When liquidation begins, release any
remaining collection reservations and notify the player that the affected cargo
is entering liquidation and is no longer earmarked for the ship. A ship still
waiting for a berth has not collected the goods. If loading is already
physically underway at the grace deadline, finish the batch committed to that
active operation. Protect only that committed batch from liquidation; other
remaining goods enter liquidation on schedule. A stock reservation, berth queue
position, or future loading plan alone gives no extension. Protected goods
continue counting against warehouse capacity until physically loaded, and cannot
be redirected or sold while handling remains committed. Expiry still cancels buy
orders backed by expired space; keeping a collection reservation does not permit
new purchases.

Within each loading source (the ship's reserved stock, then other available
owned stock), select qualifying perishables by earliest expiry first. Respect
minimum remaining shelf life and compatibility; stock that fails those checks
is not loaded simply because it expires sooner. For nonperishables, select the
oldest acquired stock first. Selection does not override other reservations or
change the owned-stock-before-market rule. Inventory cost allocation for profit
reporting follows actual batch acquisition cost as specified in section 13.

Arrival purchases use available unreserved cash at berth by default. Players may
optionally earmark an advance purchase budget for a particular stop. Reserve
that amount from company cash so other activity cannot spend it; it protects
funding, not future cargo supply, prices, or berth access. Fuel and standing
remote orders keep their separate reservations and must not share the same cash.
The stop's price and spending limits continue to apply. When an advance budget
is earmarked, purchases use only that budget, also respecting any lower spending
cap. Do not supplement it automatically from unreserved cash, sale proceeds, or
cash released from linked orders. Without an earmarked budget, use available
unreserved cash up to the stop's spending cap. A player may explicitly change the
budget subject to available funds and existing commitments. Release unused
earmarked funds to available company cash when that stop's visit finishes, or
when the stop is removed or cancelled. Do not release funds already committed
to a settled trade or handling obligation. Waiting at the same unfinished stop
does not itself finish the visit. A repeating route retains the configured
budget amount but does not carry unused cash forward automatically. Before
departing toward that stop, reserve the next visit's configured purchase budget
alongside the leg's fuel budget. Do not reserve every stop's budget at the start
of the circuit. Cash reserved for fuel and purchases remains distinct; neither
can fund the other.

Each player has one global insufficient-funds policy for automated route
departures, with no per-route override. Default to **Wait and notify**: pause
departure until fuel and the full configured purchase budget can be reserved,
or the player changes the plan or global policy. The other choices are **Sail
with a reduced budget** (fully fund fuel, then earmark available purchase cash
up to the configured amount) and **Skip purchases** (fully fund fuel and sail
to deliver cargo and collect owned stock, without new arrival purchases for
that visit). Never depart without fully funded fuel. A reduced earmarked
budget remains a strict cap at arrival, with no automatic supplementation.
Waiting ships automatically retry when available funds or relevant settings
change, rechecking the current plan and all departure requirements. Under Wait
and notify, depart once the full purchase budget and fuel can be reserved; no
manual resume is required. Notify once when a ship becomes blocked and once
when it resumes, without repeated alerts for an unchanged blocked state.
Reservation and departure must not execute twice on repeated retry events.
When several ships await funding, consider them in order of when they became
blocked and fund the longest-waiting ship whose required departure amount is
currently available. Skip unaffordable requests rather than blocking later ones.
Reserve the selected ship's full required amount before considering the next,
so the same cash cannot fund several departures. Failed retries do not reset
waiting age. Skipping alone would starve an expensive departure indefinitely
behind a stream of cheaper ones, so once a ship's wait passes a configured
threshold it may accumulate funds for a configured, time-limited window: reserve
incoming unreserved cash toward its requirement rather than funding newer cheaper
departures. Overdue bills and loan installments are paid before any new
accumulation, following section 12. At most one ship per company accumulates at a
time, the longest-waiting eligible one. The window has a fixed deadline; partial
funding and repeated retries do not extend it.

If fully funded within the window, the ship departs under normal rules. Otherwise
release its accumulated cash at the deadline, pay overdue obligations first, and
run the normal oldest-affordable departure allocation before another accumulation
attempt. Apply a configured retry cooldown to accumulation attempts so released
cash is not immediately captured again; ordinary affordable departures remain
eligible during that cooldown. Preserve the ship's original waiting age. Notify
the player when accumulation times out. Window and cooldown durations follow the
world-clock policy and remain tuning parameters. Accumulated reservations also
release under the normal rules if the player changes the plan or the policy.
Departure requirements follow the player's current global policy.
When the global Skip purchases policy is triggered for a visit, cancel the
unfilled remainder of remote buy orders linked to that visit and release their
unused cash and warehouse-capacity reservations. Notify the player of the
cancellation. Completed fills remain owned and reserved for collection because
the ship still visits that stop. Do not cancel unrelated warehouse orders.
Apply the cancellation once for that visit; cash it releases does not silently
reverse the decision to skip purchases. Fully fund fuel before departure.

Remote buy orders may optionally be linked to a particular ship collection stop.
Filled goods from a linked order count toward that stop's loading target and are
earmarked for its collection rather than offered to other ships or sales. Remote
fills still require reserved cash and compatible warehouse capacity; linking
never substitutes future ship capacity for warehouse space. Goods remain at the
purchase port and retain their acquisition cost and freshness.

Unlinked orders stay independent. A ship's purchases do not silently reduce or
cancel warehouse orders for other purposes. Linked demand must be reconciled
with cargo aboard, owned stock, and prior fills so the same shortfall is not
purchased through both the remote order and arrival instructions.

At berth, hand the linked order over to ship instructions: cancel its unfilled
remainder, release the remaining cash and warehouse-capacity reservations, and
reconcile completed fills with the ship's loading target. This handover does not
purchase replacement cargo immediately: finish planned unloading first. Then
load qualifying owned stock and purchase the actual shortfall directly aboard
within the ship instruction's price, spending, and capacity limits.
Already-filled cargo remains owned and reserved for collection; cancelling the
remainder does not undo fills. The handover is one authoritative operation so
the remote order cannot fill again while the ship buys the same shortfall.
Handling and settlement still obey the normal berth rules.

Removing or cancelling a collection stop automatically cancels the unfilled
remainder of its linked buy order and releases unused cash and
warehouse-capacity reservations. Completed fills remain owned in the warehouse;
release their collection reservation under the normal stop-removal rule. Notify
the player that cancellation occurred, identifying the ship, port, good,
cancelled quantity, released reservations, and any already-purchased cargo still
stored there. The notification reports the completed action and does not require
approval to carry it out. A delay or course change retaining the same collection
stop does not cancel the linked order. Loading-target changes automatically
reconcile linked unfilled demand and stock, cash, and warehouse reservations
with the new target, qualifying cargo aboard, and completed fills. A decrease
releases excess reservations without selling or undoing purchased cargo. An
increase requiring more remote demand must have sufficient unreserved cash and
compatible warehouse capacity; otherwise reject the combined change with a clear
explanation and preserve the previous target, order, and reservations. Apply
accepted changes as one authoritative operation to avoid duplicate demand or
partially updated plans. Ordinary handling locks still apply; a target edit
cannot reverse a settled trade or committed transfer.

Repeatable routes are available initially. They are permitted for all cargo
categories but naturally suit some better than others. Conditions can include
price and quantity limits, minimum freshness, and skipping a purchase when
previous cargo remains unsold. Auctions and contracts usually need more active
planning.

Each stop waits for its configured cargo targets, with an optional maximum wait.
When that limit is reached, finish any committed handling, notify the player of
the remaining shortfall, and continue subject to the existing departure funding
rules. Do not initiate further fills for that visit after its wait limit. Normal
visit-completion rules release unused reservations and cancel linked unfilled
orders. A repeated visit evaluates the configured targets afresh; unmet quantities
do not accumulate across visits. Existing qualifying cargo aboard still counts
toward loading targets. Berth readiness and cooldown rules govern retries while
waiting.

Players can reroute ships underway. Before confirmation, show the revised route,
arrival estimate, and additional fuel requirement. Consumed fuel remains spent.
Recalculate remaining fuel costs from the ship's current position. Reuse its
unused fuel reservation, reserve any additional required cash, and release any
excess. If the additional funding is unavailable, reject the reroute and retain
the existing route and reservations. Apply the route and funding changes together.

Instructions remain attached to their original port stops, rather than moving
automatically to a new destination. Removing a stop cancels its linked unfilled
orders and releases its reservations with notification, following the existing
collection-stop cancellation rules. Completed purchases remain company-owned.
Retaining a stop preserves its instructions and linked reservations, subject to
their normal expiry and eligibility rules.

## 9. Ships, starter packages, and purchases

Players choose among starter packages of equivalent total value, balancing fleet
value against working cash. Each provides three ships and sufficient cash for
initial cargo and voyages. No package permanently restricts later specialization.

| Package                  | Starting fleet                                           | Focus                                                      |
|--------------------------|----------------------------------------------------------|------------------------------------------------------------|
| General trader           | Three balanced freighters                                | Flexible consumer-goods routes and experimentation.        |
| Bulk hauler              | Two larger, slower bulk carriers and one small freighter | Commodities, scrap, and efficient round trips.             |
| Fresh produce specialist | Two small refrigerated ships and one standard freighter  | Perishables with conventional freight as a fallback.       |
| Oil trader               | Two small tankers and one general freighter              | Crude-oil trading with conventional freight as a fallback. |

Adjust the oil trader's starting cash to maintain equivalent total package value
and sufficient working capital for initial cargo and voyages.

Equal asset value alone does not guarantee fair earning potential. Balance risk,
working capital, and compatibility with the starting port. Players may choose
any launch port as their home port, with all three starter ships placed there.
Show local trading opportunities before the player confirms their selection.
Compare the four starter packages using fleet value, starting cash, cargo
capabilities, and operating costs. Validate comparable earning opportunities
through simulations across home ports, accounting for risk and working capital;
equivalent packages do not guarantee equal profits.

Ships have weight and volume limits and hold capabilities. Mixed cargo is
allowed when both limits and hold requirements are satisfied. Bulk goods may
fill weight capacity first; consumer products may fill volume first.

Additional ships are available immediately at fixed prices from designated
shipyards. The launch catalogue includes tankers for crude oil and refined fuel.
Both goods require liquid-compatible ship capacity and cannot use ordinary
dry-cargo holds. Capacity, size class, speed, operating costs, and cargo
compatibility distinguish ship classes. Size class governs eligibility for
size-gated berth groups and for canal transits, both specified in section 4.
Construction lead times and a general player-to-player used-ship market are
later possibilities; bankruptcy auctions already provide a separate source of
existing ships.

Shipyards buy ships back at a published fraction of current book value. One
mechanism serves both voluntary divestment and end-of-life scrapping: book value
declines under the straight-line schedule in section 13 toward its published
residual, so the buyback offer converges on scrap value without a separate rule.
A ship is eligible under the same conditions as an auction lot, with its voyage
and handling complete and free of other commitments. The published fraction is
below one, so every buyback books a disposal loss against remaining book value
under section 13 and a mistaken purchase is recoverable at a real but survivable
cost rather than being permanent. Keep the fraction configurable while preserving
terms already published.

Buyback also gives a struggling company a way to downsize instead of restarting.
That matters because the replacement-company path in section 12 is deliberately
weakened: without a divestment route, bankruptcy would be the only way to shed
unsuitable tonnage, and the design would be pushing players toward the reset it
is trying to discourage.

## 10. Voyages, labour, and port handling

Voyages progress automatically. Weather and congestion can cause visible delays
but ships do not randomly sink or lose cargo in the initial game. Show known
delays before dispatch and revised arrival estimates underway. Delay affects
perishable freshness and commercial opportunities.

Fuel is an automatically calculated voyage expense based on ship efficiency,
distance, and cargo load. Show the estimate and reserve the necessary cash before
dispatch; players do not manually manage bunkering.

Crew pay forms part of published ship operating costs and depends on ship size
and requirements. Visiting another country does not change crew wages. Port
labour affects local loading/unloading fees and handling speed. Use tunable game
values informed by geographic differences rather than exact current wage rates.
Later, mines and factories pay local wages balanced against productivity,
infrastructure, inputs, and access to buyers.

The dispatch estimate includes fuel, crew, handling, storage where applicable,
and canal fees. Ships pay the same reduced upkeep when docked or waiting at
anchorage. Voyage fuel consumption stops while waiting, but crew and applicable
refrigeration costs continue. Offline cash shortages do not immediately liquidate
ships; unpaid operating bills outside warehouse liquidation share the loan
arrears process in section 12.

Ships carry a maintenance cost that follows a published curve against age. It is
flat through the ship's useful life and rises steadily afterward, until operating
an aged hull costs more per period than the depreciation and base maintenance of
a replacement. Set the escalation so that crossover falls a defined interval past
the end of useful life, provisionally ten to twenty percent of that life, giving
players a decision window rather than a cliff.

Retirement is economic, not enforced. No ship is removed on a fixed date, and
ships still neither sink nor fail catastrophically; an owner who wants to run an
old hull on a short cheap route may keep paying for it. Publish the maintenance
curve alongside the depreciation schedule and show projected maintenance for
coming periods, so the choice between continuing and taking the shipyard buyback
in section 9 is legible in advance rather than discovered through rising bills.

Maintenance payments leave the player economy. The escalating curve therefore
drains more when the world's fleet is old and large and less when it is young and
small, which is the behavior the money-supply rules in section 5 require of the
terminal sink.

Ports have finite berths and first-come, first-served queues. Ships automatically
join on arrival. Handling takes time based on cargo quantity/type and port
capabilities. Estimates include expected queue and handling time.

Port capacity grows under sustained demand. When a port's berth utilization or
average queue wait stays above a configured threshold across a measurement window
of several game quarters, the city commits to an expansion that completes after a
published construction lead time. Warehouse capacity expands on the same basis
against the utilization measure in section 11. Trigger on utilization rather than
absolute volume, so capacity chases a target occupancy and settles there instead
of chasing traffic upward without limit.

Announce a committed expansion, its size, and its completion time when it is
committed, and never sooner than the lead time before it takes effect. Players
route ships and take leases days ahead against current congestion, so capacity
must not change silently. The lead time is what keeps congestion a real
constraint: expansion relieves a chronically overloaded port over weeks, not a
busy afternoon.

Berth capacity may also contract after sustained low utilization, provided no
berth being removed is occupied or committed. Warehouse capacity does not
contract. Reducing it would raise the utilization of every remaining tenant and
therefore their renewal quotes, through an invisible operator action rather than
market demand; and outstanding leases make the space genuinely unavailable to
reclaim. Expansion is consequently close to irreversible, so set triggers
conservatively: an over-eager threshold permanently over-builds a port.

Cities expand their own ports in the initial game. Player-funded port
infrastructure belongs with the facility rules deferred to section 14. Thresholds,
measurement windows, lead times, and expansion increments are configurable.

After handling, ships vacate their berth. Ships waiting for better prices move
to anchorage and must regain a berth to unload or load. Warehouse goods remain
tradable without occupying a berth. Anchored ships waiting for trading conditions
automatically rejoin the berth queue when current prices, qualifying available
goods, funds, and capacity permit an intended operation. Queue entry does not
reserve a trade or guarantee its price; conditions are checked again when the
ship can begin the relevant handling phase. Keep at most one queue entry per
ship. If conditions become unviable while queued, keep the ship's position until
it is considered for berth assignment. Recheck then: if any planned operation is
viable (including collecting owned stock or unloading into reserved storage),
assign the berth; otherwise return the ship to anchorage without occupying it.
This check does not settle a trade or lock a future loading price. Prevent rapid
repeated unsuccessful queue attempts with a minimum cooldown after a failed
pre-assignment check, provisionally five real minutes and configurable. During
the cooldown, relevant market, stock, funds, and capacity changes may update
viability but cannot trigger re-entry early. At cooldown expiry, rejoin if an
operation is now viable; otherwise wait for a relevant change that makes it so.
Do not require an additional change after expiry if viability already recovered.
Re-entry takes a new queue position and retains the one-entry-per-ship rule.

## 11. Warehouses and leases

Every port has finite rentable warehouse capacity. Ordinary, refrigerated, and
liquid storage have separate availability and demand-dependent prices. Crude oil,
refined fuel and vegetable oil each require their own compatible liquid-storage
allocation rather than ordinary or refrigerated space, and food-grade oil cannot
occupy space that held either petroleum product without the cleaning in
section 6. Each storage type uses a smooth utilization
curve with a port-specific base rate and a steeper increase near full capacity.
Utilization counts capacity leased or otherwise unavailable, including empty
leased space, grace-period occupancy, liquidation occupancy, and protected
unloading. Do not count cargo or reservations within an already-counted lease a
second time. Quotes apply to new leases and renewal offers; existing fixed rates
and six-hour renewal quotes remain protected. Simulated procurement is a large
and easily overlooked driver of these quotes. Computer buyers reserve full
receiving capacity when posting a request under section 7, and reserved capacity
counts toward utilization, so the volume of system-generated procurement sets a
floor under every player's warehouse rent at that port. Tune procurement volume
and port warehouse capacity together against the resulting rent rather than as
independent knobs, and include simulated reservations when validating the curve.
Price each added block along the utilization curve, accounting for the capacity
already allocated by preceding blocks in the same request. Show one total quote
before purchase; do not price the entire request at its starting utilization.
Accept the quoted allocation as one operation, re-quoting if availability or
price changes before acceptance rather than silently charging a different total.
Curve parameters remain tunable.

The convex curve is also the intended deterrent against hoarding. Because
utilization counts empty leased space, a company can raise rivals' rents and deny
them room by leasing capacity it does not need, and that is treated as a
legitimate but expensive strategy rather than an exploit. Each additional block is
priced further up the curve, rent is paid in full upfront, and early release
refunds only part of the unused term, so cornering a port costs superlinearly and
the cost lands entirely on the company attempting it. Do not add a per-company
share cap or an idle-space surcharge unless play shows both deterrents failing: a
cap also constrains legitimately large operators, and a surcharge penalizes
pre-positioning for an inbound delivery or an awarded procurement contract.
Validate the curve's steepness against a deliberate cornering attempt during
balancing, and treat a successful cheap corner as a signal to steepen it.

Sustained capacity growth under section 10 is the structural answer, and the
stronger one. Hoarding raises measured utilization, which is precisely the trigger
for expansion, so a company that corners a port funds the construction that
dilutes its own corner once the lead time elapses. Cornering is therefore not
merely expensive but self-defeating, and the design does not need a rule that
forbids it. The lead time means the corner still bites in the short run, which is
what keeps the strategy worth attempting and worth defending against.

Berth capacity needs no equivalent rule. A ship whose planned operation has become
unviable is returned to anchorage at assignment rather than taking a berth, as
specified in section 10, so holding a queue position denies nothing. A nominally
viable trivial instruction can claim a berth, but handling time scales with cargo
quantity, so it also releases the berth almost immediately.

New leases start immediately. Players securing capacity for a future delivery
rent it now and maintain sufficient coverage; arbitrary future-dated new leases
are not offered. Renewals alone can secure the next term in advance under the
existing six-hour priority and locked-quote rules. Computer buyers likewise
secure capacity before posting procurement requests. Neither new leases nor
renewals may double-allocate space protected for unfinished transfers.

Warehouse capacity is measured in volume blocks (cubic metres), with no separate
weight allowance. Goods consume warehouse space according to their volume;
ordinary, refrigerated, and liquid space retain their compatibility
requirements. Ships continue to enforce both weight and volume limits. Exact
volume per block is configurable and remains a balancing choice.

Players rent these blocks with a choice of one-, three-, or seven-real-day leases.
There is no automatic discount for longer terms initially: longer leases secure
capacity and a fixed rate while committing the player to more rent. Keep offered
terms configurable for future leases without changing existing commitments.
The rate stays fixed for the lease term; new leases and renewals use the current
market rate. Pay the full rent upfront when acquiring or renewing a lease;
accept the lease only if unreserved cash covers the payment. For profit and ROI,
record prepaid rent as an asset and recognize its expense over the lease term.
Include its remaining prepaid value in capital employed, avoiding both an
immediate full operating loss and double counting the cash already paid.
Players may terminate a lease early, or release whole rented blocks, only when
the released capacity is empty and free of reservations and handling commitments.
Refund 50% of the unused prepaid rent attributable to that released capacity,
provisionally; make the refund fraction configurable for future leases and
preserve each existing lease's disclosed terms. Release the capacity immediately.
Remove its remaining prepaid asset value, return the refund as cash, and recognize
the nonrefunded portion as an expense, rather than continuing to amortize it.
Ordinary expiry has no unused prepaid term to refund. Cancelling an order or bid
alone does not terminate its supporting lease or trigger a refund.

Leased capacity is exclusive to the company during its term. Cargo and purchase
reservations must fit. Expansion requires available space; reductions require
existing cargo and reservations to fit in the remaining capacity. Players can
set storage spending limits; instructions cannot exceed them to unload cargo.

Lease expiry has advance notice and optional auto-renewal with a maximum rate.
Existing tenants receive a limited renewal-priority window before expiry for
their currently leased capacity. During that window they have first refusal at
the current quoted renewal rate; renewing requires full upfront payment.
Auto-renewal acts within the window if the quote meets the player's rate cap and
unreserved cash covers the full rent. Priority does not cover additional space.
After the window ends, unrenewed space has no tenant preference and becomes
available to others only once physically cleared and free of commitments.
The priority window runs during the final six real hours before lease expiry.
Keep its duration configurable for future leases while preserving already
published windows. Renewal must be accepted before expiry. Lock the renewal
rate quoted when the six-hour window opens for the entire window; later demand
changes do not alter that offer. Once accepted, it remains fixed for the renewed
lease term. The renewed term begins at the existing lease's expiry, not at early
acceptance.

Auto-renewal attempts when the window opens if the locked quote meets the
player's cap and unreserved cash covers the full rent. If cash is insufficient,
retry when funds become available before expiry. Re-evaluate if the player
changes renewal settings; no renewal may execute more than once. A quote above
the cap remains unaccepted unless the player changes the cap or renews manually.
This quote lock affects renewals only; new leases use their current market quote.
If not renewed:

1. Cancel open buy orders using that capacity.
2. Allow a 12-real-hour grace period for sale or collection of existing goods;
   no new cargo can enter the expired space. Perishable aging continues. Keep
   this duration configurable for future expiries; an active expiry retains its
   disclosed deadline.
3. After grace ends, fill existing compatible local buy orders first, respecting
   their price, quantity, freshness, and receiving-capacity requirements. Offer
   the remaining usable goods in a computer-run liquidation auction, then clear
   anything still unsold through the system fallback. This is forced liquidation,
   not continued execution of the owner's minimum sale price.
4. Deduct outstanding rent and handling costs and credit net proceeds to the
   company. Release storage as goods physically leave it or transfer to valid
   buyer storage allocations. Unsold goods awaiting auction or clearance still
   occupy port capacity; the lease ending does not make that space available.
   Perishables continue aging, and expired goods are discarded.

Cargo auction bids require lease coverage from the outset through auction close,
so capacity to receive a won lot exists at settlement. Coverage beyond closing is
not required. Instead, a won lot whose supporting lease expires receives its own
configured grace period, provisionally 12 real hours to match ordinary lease
expiry, running from the later of settlement and lease expiry. Within it the
winner may sell the lot, load it aboard a ship, or acquire a replacement lease
for its occupied blocks under the rule below; afterwards it enters the ordinary
liquidation sequence.

During this post-auction grace period, the winner may replace the expired lease
for the occupied blocks by paying the full rent upfront at the current new-lease
quote for a supported term. The replacement starts immediately. The old renewal
quote and renewal priority have expired; this is an explicit replacement-lease
exception for the space already occupied by the won cargo, not a late renewal or
a right to additional blocks. Accrued grace charges remain payable.

Price the replacement against current utilization with the occupied blocks
counted once, using the normal progressive block calculation without adding a
second allocation for the same space. Atomically replace the grace allocation
with the new lease and retain cargo ownership and location. Insufficient funds
leave the grace state and deadline unchanged. Successful replacement ends grace
for those blocks and prevents their pending grace liquidation. It neither revives
goods already in liquidation nor postpones liquidation of unrelated expired stock.

Requiring coverage well past closing was the alternative and was rejected.
Renewals are offered only in the final six hours before expiry, so a bidder whose
lease ended shortly after an auction would have had to lease duplicate blocks
purely to qualify, paying twice to store one lot and thinning the bidding on lots
that already attract few bidders. The grace period keeps the entry bar at
"capacity exists when the lot settles" while leaving the winner responsible for
finding storage or a buyer.

This grace occupies port capacity and counts toward the utilization curve on the
same terms as ordinary expiry grace, charged at the previous lease rate. It does
not extend the lease, admit any other cargo, or postpone liquidation of goods
already sitting in an expired lease. Procurement
auctions reserve the full receiving capacity at posting, with lease coverage
from earliest delivery through the deadline plus an unloading allowance as
specified in section 7. Buyers cannot reduce or release that committed capacity.
For settled procurement deliveries, protected completion retains receiving space
through any unloading overrun, with the disclosed overrun charge paid by the
buyer. This is an exception to the ordinary ban on incoming cargo after expiry,
limited to that already-committed delivery; it does not admit new purchases.

Block size, utilization-curve parameters, and numerical billing parameters
remain tuning choices. Use one liquidation accounting pool per expired lease,
combining proceeds from its order-book sales, auctions, and final clearance.
Deduct only that lease's unpaid storage and handling costs, capped at the
combined proceeds. Keep different leases separate; neither a shortfall nor spare
proceeds migrate between their liquidation pools. Dividing cargo into multiple
lots does not change the accounting pool or charge cap. Outstanding storage and
handling charges collected through expired-lease liquidation are capped at that
lease's liquidation proceeds. The port absorbs any shortfall: do not debit other
company cash, create an overdue balance, or trigger bankruptcy for it. Net
proceeds to the owner cannot be negative, and clearance completes regardless of
the shortfall. This cap does not refund charges already paid or cap unrelated
operating obligations.

During the grace period, occupied space is charged at the previous lease rate.
When liquidation begins, apply a fixed surcharge above that rate, provisionally
25%. Lock that liquidation rate rather than tracking subsequent market changes,
and show both rates in expiry warnings. Charges continue only for space still
occupied through the order-book, auction, and clearance stages; release of space
stops its charges. Deduct unpaid charges from liquidation proceeds. The
surcharge is configurable for future expiries; changing it does not alter rates
already disclosed for an expiry in progress. Liquidation cargo normally enters
the next scheduled port auction whose bidding has not yet opened, preserving its
full bidding window and locked lot terms. Perishables instead use expedited
computer-run auctions with a shorter, two-real-hour bidding window,
configurable, and a fixed closing time. Show projected freshness. If the goods
cannot last through closing, use immediate clearance while usable or discard
them if expired, as specified in section 7. Goods stay counted against port
storage through the auction and final clearance. Final clearance pays a
discounted configured reference value for each good, adjusted downward for
deterioration. Start with a provisional 10% of reference value before freshness
adjustments; the rate and reference values are tunable. Use configured reference
values rather than recent local trade prices or the owner's purchase cost.
Expired perishables receive no payment and are discarded. Cleared goods leave
port storage, releasing capacity instead of accumulating in a new simulated
warehouse. Credit proceeds through the normal liquidation accounting after
outstanding charges; freshness adjustment details remain open. Ordinary lease
liquidation returns net proceeds to its owner; bankruptcy liquidation does not.
If the owner becomes bankrupt during lease liquidation, continue the existing
process and auctions without restarting them. Net proceeds not yet paid to the
owner then leave the economy; amounts already paid remain assets of the old
company subject to bankruptcy cleanup. Nothing transfers to the replacement
company. Do not sell the same lot again or charge the same cost twice when
ownership enters bankruptcy administration. Timing of ordinary net payouts must
respect the aggregate per-lease cap as remaining charges accrue. The order-book
→ auction → clearance sequence applies to expired warehouse leases; bankruptcy
asset auctions retain their separate rules.

## 12. Loans and bankruptcy

A simulated bank offers fixed-interest loans with automatic installments, a
visible repayment schedule, and penalty-free early repayment. Other players do
not lend money. Assets, earnings, existing debt, and account bankruptcy history
inform borrowing limits and terms. Successful repayment should improve access
over time; past bankruptcy must not make recovery impossible.

Initial borrowing limits are based on a conservative fraction of fleet value.
Sustained profits unlock additional credit as the company establishes an
earnings history. Existing debt reduces remaining borrowing capacity, and account
bankruptcy history affects limits and terms. The valuation method, lending
fractions, and earnings thresholds remain configurable tuning parameters.

Installments and operating bills are collected automatically. Overdue bills and
loan installments are paid oldest due first from available unreserved cash,
before new spending or reservations. Retry automatically when unreserved cash
becomes available. Existing reservations and committed operations remain
protected; committed voyages and handling finish.

A missed installment or operating bill blocks further borrowing and starts one
shared, configurable 24-real-hour grace period from the first missed payment.
Warehouse liquidation retains its separate proceeds-capped rules. Show the
arrears, deadline, and warnings. Partial payments reduce arrears without
resetting the deadline; subsequent missed payments do not extend it. Clearing
all overdue bills and installments ends the grace period. Remaining arrears at
the deadline trigger forced bankruptcy. Voluntary bankruptcy is also available.
Interest rates and other numerical lending parameters remain tunable.

Only player companies can go bankrupt; simulated city actors remain operational
under the resource constraints in section 5.

Bankruptcy closes the old company to new business immediately, cancels ordinary
trading instructions, and clears its loan debt. Its unsettled awarded supplier
contracts default immediately: reserved deposits go to the computer-controlled
buyers, whose payment and receiving reservations are released. Already-settled
sales finish handling. There are no player-buyer procurement contracts initially.
A 20-real-minute cooldown begins when bankruptcy is declared, voluntarily or
through default. After it expires, the player may create a replacement company
and receive a starter package without waiting for liquidation to finish. The
cooldown survives sign-out or restart and is not bypassed through another account.
Show the remaining time; inspecting the world remains available. No old assets or
auction proceeds pass to that replacement company; bankruptcy count and company
history persist.

The replacement package shrinks with the number of counted prior bankruptcies,
down to a configured floor that keeps recovery possible as required above. A
geometric reduction toward a floor near half the base package is the provisional
shape; ratio and floor are tuning parameters. Voluntary and forced bankruptcy
count alike, or the distinction itself becomes the exploit.

Counted bankruptcies age out after a configured number of game years and stop
reducing the package, while the lifetime count remains permanently visible on the
account and in the rankings. Sustained solvent operation therefore restores full
onboarding, consistent with the lending rule that past bankruptcy must not make
recovery impossible. Dormant closures under section 5 are recorded separately and
never reduce the package.

Assets enter auctions as separate lots: individual ships, cargo batches at their
ports, and eventually complete facilities. Purchases of cargo do not move it.
The former owner cannot bid on their company's liquidation through the new
company. Auction payments leave the economy; creditor repayment is not simulated.
Loan losses may be measured internally for balancing.

Ships already at sea complete their current voyage and handling before their
lots become available; cargo lots must be ashore and free of commitments.
Perishable lots need shorter sale windows and keep aging.
A simulated liquidator provides a low fallback purchase price for unsold assets
so liquidation can finish. No proceeds return to the former owner. Ships taken by
the fallback liquidator are scrapped and leave the world rather than re-entering
the fleet; otherwise aged, high-maintenance hulls would recirculate indefinitely
and defeat the retirement economics in section 10.

Bankruptcy administration cancels open buy orders and unawarded bids, releasing
their reservations into the old company's estate. Cancel ordinary standing sell
orders and route instructions, but preserve already-settled trades and active
handling. Auctions already accepting bids on company consignments continue on
their published terms; other available company goods enter liquidation. Do not
restart existing lease-liquidation auctions or offer the same goods twice.

Complete current voyages and committed handling automatically. Sold cargo belongs
to its buyer even if still aboard an estate-owned ship and must never enter the
estate's asset auctions. Clear the ship's handling commitments before offering it
for sale. Use remaining company cash for necessary voyage, handling, and storage
expenses during liquidation. The system absorbs any shortfall so inadequate
estate cash cannot strand ships or block port storage indefinitely. This support
funds completion and liquidation, not new speculative voyages or purchases.

Release empty, uncommitted warehouse capacity; retain occupied or committed space
only until goods clear and transfers finish. Remove residual estate cash and
liquidation proceeds from circulation after necessary expenses, without passing
any value to the replacement company. Ship inspectors see the public bankruptcy
label specified in section 4 throughout estate ownership.

Loan-funded value transfers followed by bankruptcy must not be an easy source of
money for accomplices. Each player may operate one active company; alternate
accounts cannot collect extra starter grants or evade bankruptcy history and
cooldowns. The invitation requirement in section 2 is what makes that limit
enforceable: accounts are rate-limited by invites earned through sustained play,
and the recorded invitation tree localizes any surviving alternate accounts to
an identifiable subtree. There are no direct cash or asset gifts initially:
transfers use the established markets and auctions. Block self-trades and bids
on a player's own consignments or former company's liquidation. Log suspicious
reciprocal trades and unusual prices for review without automatically penalizing
legitimate bargains, weighting activity concentrated within one invitation
subtree most heavily. Track repeated resets and apply the agreed
bankruptcy-history effects on lending and on replacement starter packages.
Identity enforcement and review procedures are implementation and operations
work; these rules do not imply detection is already implemented.

## 13. Profit, valuation, and ROI

Period ROI = period net profit / average capital employed during that period.

Capital employed includes cash, inventory, ships, and eventually facilities,
including assets funded through loans and the unexpired prepaid value of leases.
Borrowing does not shrink the denominator to shareholder equity. Starter grants
and loan proceeds are not profit.

Trading profit is recognized when goods sell, accounting for their purchase
cost. Unsold cargo stays at purchase cost rather than rising with quoted prices;
spoilage records a loss. Interest, crew, fuel, handling, storage, and other
operating expenses reduce profit. Buying a ship is not an immediate operating
loss; ships and facilities follow a published depreciation schedule.

Use fixed world-wide quarterly and yearly reporting periods. Profit and ROI are
visible immediately, but partial-period company results are labelled provisional
and unranked. Ranked quarterly ROI requires participation throughout that entire
quarter; ranked yearly ROI requires the entire year. Do not annualize partial
results or rank younger companies against full-period participants. A company
joining mid-quarter first becomes eligible after its next complete quarter.
This replaces the earlier age-only one-quarter eligibility rule. A restarted
company has its own results and eligibility clock; account history persists.
The first complete reporting year likewise determines yearly eligibility.

Track each cargo batch's actual acquisition cost; partial sales recognize the
cost attributable to the quantity actually sold. Internal transfers retain that
cost and do not realize profit. Usable cargo remains at cost through changes in
freshness grade; recognize losses when it expires or sells below cost rather
than marking it to changing market quotes. Discarded expired quantities are
written off once, including cargo that expires during handling.

Ships and facilities use straight-line depreciation over published useful lives,
down to published residual values. Asset disposal profit or loss is sale proceeds
minus remaining book value, including auction sales, shipyard buybacks, and
scrapping. Useful lives and residual values are tuning parameters, and because
they influence replacement decisions and buyback amounts in section 5 they are
economic parameters rather than presentation choices; depreciation itself does
not remove cash. Buyer asset cost is the actual purchase price, not the seller's
book value. Escalating maintenance under section 10 is an operating expense of
the period in which it is charged, not a capitalized cost or an adjustment to
book value.

Reserving or returning a performance deposit is not income or expense; it
remains the supplier's restricted cash asset until returned or forfeited.
Forfeiture is a supplier expense and recipient income, without also counting
the same funds as a procurement payment. Reservations do not create new assets
or remove existing capital merely by restricting its use.

Calculate average capital using time weighting over the reporting period:
each recorded capital value contributes in proportion to how long it applied.
A last-minute asset change must not revalue the whole period's denominator.
If average capital is zero, display ROI as unavailable, never infinite or ranked.
Exact world-calendar anchoring is settled with the world-time decision. Public
holdings and market quotes must not create artificial profit on paper.

## 14. Later expansion

Players can eventually build production facilities at cities:

- **Mines** extract raw materials for trade or industrial use.
- **Farms** produce grain, fruit, spices, and livestock/meat. Climate, land
  availability, and perishability shape suitable locations and shipping needs.
- **Sawmills** produce lumber for steady construction and manufacturing demand,
  using abstract local timber inputs until a separate tradable input is approved.
- **Refineries** consume crude oil and produce refined fuel, connecting inbound
  and outbound tanker routes.
- **Factories** consume inputs and produce manufactured goods. Vegetable-oil
  processing belongs here, with agricultural inputs abstracted until its recipes
  are designed.

Machinery serves industrial expansion. Local labour, productivity,
infrastructure, transport, and buyers determine viable locations. All facilities
follow the shared world-clock rules: production continues while the world is
operating and pauses during hosting suspension or outages, without catch-up.

Industry extends the shipping economy rather than replacing it with disconnected
passive income. Simulated production and end-user demand remain. Construction,
land availability and limits, recipes, production cycles and capacity,
construction costs, and facility ownership rules have not yet been designed.

Carriage for hire is a second later possibility. In the initial game a company
profits only on goods it owns, by moving them to a better price. Real short-haul
shipping between neighbouring ports instead earns a freight rate for carrying
another party's cargo, usually feeding a mainline vessel at a hub. Without that
mechanic the economic function of a port cluster cannot be expressed, which is
why section 5 bounds simulated price spreads within a catchment: it prevents the
cluster from paying out as arbitrage instead. Adding carriage later would let
those clusters work as the feeder networks they represent, and would give small
and size-restricted ships a role beyond owning cargo. Rate setting, capacity
commitments, liability for late or spoiled cargo, and interaction with the
existing reservation rules are undesigned.

Luxury vehicles are a third. The roster would support them well — German marques
behind Hamburg, Japanese ones at Tokyo, Italian production through Antwerp's
inland catchment — but they do not fit the luxury category as section 6 defines
it. That category's gameplay identity is high value in little space, which lets
even a small freighter carry a fortune; cars are high value in a great deal of
space, so only the largest ships could trade them and the distinction from mass
consumer products would collapse. They also move as roll-on cargo rather than in
any hold type section 9 defines. Adding vehicles therefore means adding a
vehicle deck as a capability alongside dry, refrigerated and liquid capacity,
and is deferred until then rather than forced into a luxury slot.

Additional construction materials can follow lumber once facility
construction exists. Cement, gypsum and architectural glass have real sources on
the roster that barely overlap iron ore's — Abu Dhabi, Valencia, Ho Chi Minh
City, Shanghai and Guangzhou are all ore importers that would gain a bulk export
— so they would add route variety. They are deferred because they add no
mechanic at launch. Unlike the liquid catalogue, where three goods and a
hold restriction left tankers with no backhaul, dry ships may already carry any
of the nineteen dry goods, and scrap is designed as their return cargo. These
additional materials would currently trade much like iron ore, into simulated
demand only, and would tip the catalogue toward large tonnage. Once players
build facilities, the same goods become inputs to a build decision with a
player-facing sink, which is when they earn a slot. Cement additionally needs
pneumatic discharge rather than an ordinary hold, and glass's defining trait is
fragility, which section 10 rules out by design; both want capability work
alongside the goods.

## 15. Implementation boundary and invariants

The current repository implements an in-memory shared world and guest lobby,
not this economy. Verified design entry points are:

- [`Domain.World`](../lib/tijara_tides/domain/world.ex): world identity only.
- [`WorldCommands`](../lib/tijara_tides/use_cases/world_commands.ex): all gameplay
  commands currently rejected.
- [`WorldServer`](../lib/tijara_tides/infrastructure/world_server.ex): one local
  authoritative owner, connection roster, and public lobby snapshots.
- [`GuestSession`](../lib/tijara_tides_web/plugs/guest_session.ex): browser guest
  identity, not authenticated account ownership.

See [ARCHITECTURE.md](../ARCHITECTURE.md) for implemented layers and operational
limits. This document does not select database schemas, APIs, a tick scheduler,
or a transaction model. Authentication, durable recovery, command deduplication,
and economic settlement must be designed before valuable persistent assets.

Implementation must preserve these gameplay invariants:

- A resource cannot be simultaneously spent, sold, reserved, or allocated twice.
- Cargo has one owner and one physical location; remote trading does not
  teleport it.
- Ships and warehouses cannot exceed compatible capacity, including reservations.
- Physical loading/unloading requires berth access and handling time.
- A settled trade transfers money and ownership once; physical handling retains
  capacity commitments and prevents reuse of cargo until transfer is complete.
- Asset auction settlement transfers ownership and payment at closing; procurement
  award creates a contract and does not pay for an undelivered shipment.
- Prices and quantities used for a trade satisfy the applicable limits.
- No response carries another company's manifest contents, batch acquisition
  costs, exact freshness, trading instructions, limit orders, or sealed bids, and
  no aggregate permits a single company's holdings to be read back out of it.
  Observable physical facts are public by design and do not breach this; section
  4 enumerates them.
- Disconnecting does not reset obligations; retries or recovery do not duplicate
  trades, production, loan charges, auctions, or starter grants.
- Bankruptcy resets the company, not the account's history, and does not transfer
  old assets into the replacement company.
- Every economic timer uses a defined clock and an explicit offline/recovery rule.
- The price level is anchored to configured reference values that are never
  derived from observed trade history, so nominal results stay comparable across
  the world's whole lifetime.
- Every cash flow across the player-economy boundary has a defined source or
  sink. Cash stock includes reserved cash and is reconciled independently of
  accounting profit; depreciation is not a cash sink. Ship purchases and
  maintenance remove cash, while buybacks add it.
- Ship population has a terminal sink: hulls leave the world through scrapping
  and are never recirculated by a fallback liquidator.
- Simulated demand scales with currently active companies, never with a
  cumulative count of accounts ever created.
- Account creation consumes an earned invitation entitlement through a single-use
  code or emailed magic link, and records the inviter permanently. Unused expiry
  restores quota exactly once. Shareable codes create unlinked accounts; emailed
  links verify and link their recipient email on redemption. Later identity
  linking remains optional and verified.

These are requirements for future implementation and meaningful tests, not
claims that the current lobby provides them. Order history, route evaluation,
market simulation, and map updates will also need bounded processing and
retention policies as the persistent world grows.

## 16. Remaining decision checklist

The discussion audit tracks 23 initial-game product decision groups below: **all
23 complete**. These are grouped decisions, not a count of every
implementation edge case. Completed decisions remain in the main sections; this
checklist replaces the earlier review table that mixed resolved and unresolved
items. Track progress against these groups rather than treating each tuning
constant as a new product question. Newly discovered material conflicts may
change the list.

1. **Complete — Markdown defaults and edits:** require every grade percentage,
   split mixed-grade stock into separately priced portions, and preserve the
   initial asking-price basis unless explicitly changed.
2. **Complete — Auction eligibility and deadlines:** no self-bidding or
   coordinated price manipulation; active companies with deposits can bid without
   owning cargo upfront; backing must be valid at close; delivery deadlines are
   inclusive when qualifying unloading can begin. Deposits reserve 10% of the
   buyer's maximum before award and retain 10% of awarded payment afterward.
3. **Complete — Other auction schedules:** procurement requests and ready
   bankrupt assets join the next unopened scheduled port auction. Perishable
   liquidation uses configurable two-hour auctions, bypassed for clearance or
   disposal if the goods cannot remain usable through closing. Bidding window
   length is configured independently of the auction interval, so raising
   frequency never shortens the window; overlapping windows are expected and
   their liquidity cost is managed by batching same-good lots.
4. **Complete — Procurement receiving exceptions:** validate coverage before
   posting, preserve receiving space and computer-buyer funding through overruns,
   and protect cargo/deposit/deadlines while retrying acceptance after a system
   fault. Supplier-caused lateness remains subject to default.
5. **Complete — Warehouse allocation pricing:** price added blocks progressively
   along the utilization curve with a total quote before acceptance. New leases
   start immediately; only renewals secure a subsequent term in advance.
   Won auction cargo in post-expiry grace may acquire a replacement lease for its
   occupied blocks at the current new-lease quote, with upfront payment, accrued
   grace charges retained, and no duplicate capacity allocation or late renewal.
6. **Complete — Liquidation accounting scope:** pool proceeds and capped charges
   per expired lease, never across leases. Bankruptcy continues existing
   liquidation without restarting auctions; unpaid net proceeds leave the
   economy and amounts already paid remain old-company assets.
7. **Complete — Bankruptcy cleanup:** cancel unawarded bids and ordinary orders,
   preserve active consignment auctions and settled handling, finish voyages,
   fund necessary completion from estate cash with system fallback, release
   cleared storage, and remove residual value. Public ship inspection clearly
   identifies bankruptcy without revealing private cargo.
8. **Complete — Abuse controls:** one active company per player with no alternate-
   account grant/history evasion, no direct gifts, blocked self-trades and
   prohibited bids, suspicious-trade review, and a 20-real-minute bankruptcy
   restart cooldown. Account creation consumes an earned, non-transferable,
   expiring invitation, and the recorded invitation tree both rate-limits new
   accounts and localizes collusion review to subtrees. Replacement starter
   packages shrink with counted bankruptcies down to a floor, with counts aging
   out while the lifetime total stays visible. Procurement deposits use buyer
   maximum/awarded payment. Concrete detection and review mechanisms remain
   implementation work.
9. **Complete — Inventory and asset accounting:** actual batch acquisition cost,
   no write-down of usable cargo solely for age, loss at expiry or below-cost
   sale, straight-line depreciation to residual value, disposal gains/losses
   against book value, and deposits expensed only on forfeiture.
10. **Complete — Leaderboard periods:** fixed world-wide periods, time-weighted
    capital, full-period quarterly/yearly eligibility, provisional unranked
    partial results, no annualization, and unavailable ROI at zero average
    capital. Absolute quarterly profit is ranked only for the three most recent
    completed quarters, with yearly profit the measure beyond that horizon; the
    section 5 price anchor keeps nominal results comparable, so no inflation
    adjustment is applied. Exact calendar anchor follows the world-time decision.
11. **Complete — Loan terms:** conservative fleet-based initial limits,
    sustained profits unlocking additional credit, and existing debt and account
    bankruptcy history affecting access. Oldest overdue installments take
    priority over new spending from unreserved cash; existing commitments are
    protected. Missed payments block borrowing and start a configurable
    24-real-hour grace period; partial repayment does not reset it, clearing
    arrears ends it, and remaining arrears at expiry trigger bankruptcy.
    Numerical rates remain tunable.
12. **Complete — Idle costs and unpaid operations:** anchorage and
    docking use the same reduced upkeep, with crew and refrigeration continuing
    but voyage fuel stopped. Operating bills outside warehouse liquidation share
    the loans' 24-hour arrears process and oldest-due payment priority. Committed
    voyages and handling finish; clearing all arrears ends grace, while partial
    payments and later missed bills do not reset the deadline.
13. **Complete — Route stop completion:** cargo targets with an optional maximum
    wait; on timeout finish committed handling, notify shortfalls, and continue
    subject to departure funding. Repeated visits use fresh targets without
    accumulating unmet quantities, while counting qualifying cargo already aboard.
    Departure-fund accumulation has a fixed timeout; on expiry release cash,
    pay arrears, and fund affordable departures before retrying accumulation
    after a cooldown. Retries retain waiting age without extending the window.
14. **Complete — Reroute funding:** recalculate from current position, reuse
    unused fuel reservations, release excess, and retain the old route if extra
    funding is unavailable. Instructions stay with their original stops;
    removing a stop cancels linked unfilled orders and releases reservations
    with notification, while completed purchases remain owned.
15. **Complete — Freshness and handling presentation:** updated arrival and
    post-unloading freshness estimates include expected queues and handling.
    Storage-type transfers take time and require compatible receiving capacity;
    refrigeration never restores freshness. Interrupted handling resumes saved
    progress with ownership and capacity reservations preserved.
16. **Complete — World time and outages:** one real week per quarter and
    four per 52-week game year, with a shared published reporting calendar.
    Normal direct voyages take at most 24 real hours even for the slowest ship;
    the shortest routes take under 15 real minutes for every eligible ship.
    Weather and queues may add time. Simulation continues through the host's
    awake idle interval after the last player disconnects. Hosting suspension
    and game-wide outages pause every world timer together, without catch-up;
    player timers, meaning owner absence, its closure warning, and activity
    weight decay, run on wall-clock time and never pause. Every duration is real
    time unless marked a game period; ship useful lives, depreciation, and loan
    interest and installments are quoted in game time and displayed alongside
    their real equivalents.
17. **Complete — Authentication experience:** no passwords; invite redemption
    creates an account and device session without email or Google. Optional
    verified linking at any time supports email magic links on web and native
    Linux, plus Google on the web, for cross-device access to the same account,
    company, and history. Inviters choose an emailed magic link that links the
    recipient's email on redemption, or a shareable code that creates an unlinked
    account. Both expire after a configured few days and restore inviter quota
    exactly once if unused; email-verification credentials are never shown to
    inviters. Unlinked accounts are prompted to link once their company holds
    meaningful assets, and accept permanent loss on device-session loss plus
    in-app-only notices until they do.
18. **Complete — Map and initial world:** Equal Earth, clickable ships
    and ports, route overlays, and port panels for markets, auctions, storage,
    and congestion. The user supplied 25 required locations in section 4;
    these are the default launch roster, and section 4 now resolves every
    city-to-harbor mapping that was ambiguous. Ports admit ships by size class
    through per-berth-group limits, splitting Ho Chi Minh City and Shanghai and
    capping Houston, and waterways carry their own limits, with the Panama Canal
    closed to the largest class. City economic identities are assigned in the
    launch port roster. Additions may be proposed only for important gameplay
    balance needs and require the user's approval.
19. **Complete — Initial fleet and onboarding:** any launch port may be
    selected as home port, with all three starter ships placed there and local
    trading opportunities shown before confirmation. Four starter packages include
    an oil trader with two small tankers and one general freighter, with adjusted
    working cash for equivalent total value. Compare fleet value, starting cash,
    cargo capabilities, and operating costs; validate comparable opportunities
    through simulations across home ports without guaranteeing equal profits.
20. **Complete — Simulated economy:** gradual production and consumption, capped
    buyer-budget replenishment, and bounded price responses to surplus and
    shortages. Factories consume inputs and start with inventories; raw-resource
    producers need no imported inputs. Recipes use catalogue goods where
    relevant and abstract other materials as local production costs. The 22-good
    catalogue is final, and city-level supply and demand are assigned per port
    in the launch port roster, which carries a generated coverage check. Ports
    sharing a regional catchment use a shared regional operating price driven by
    actual inventories and demand within fixed global bands, with jointly
    bounded local quote adjustments keeping simulated spreads near transport
    cost. Player orders remain unrestricted. Simulated bidders carry private
    valuations around reference value so player consignments face real
    competition at ports with buying demand. Other ports permit player-only
    luxury auctions with a clear no-simulated-buyers notice. Numerical response
    parameters are tuning work.
21. **Complete — Monetary anchor and participation scaling:** absolute configured
    reference values and bands fix the price level and are never derived from
    observed trade history. A decaying per-company activity weight, capped at 1
    and summed globally, scales simulated budget replenishment and producer output
    so depth follows current participation rather than cumulative signups.
    Dormancy instead uses owner absence, reset by an authenticated visit but not
    automated company activity. Advance notice precedes closure; an owner return
    before closure cancels it. Dormant companies are removed from the activity
    index and liquidated without incrementing the bankruptcy count. Player cash
    stock, including reservations, is tracked separately from accounting profit
    through explicit sources and sinks.
    Ship replacement removes cash; depreciation itself does not. Cash stock is
    instrumented rather than targeted.
22. **Complete — Ship lifecycle and divestment:** shipyards buy ships back at a
    published fraction of current book value, serving both voluntary divestment
    and end-of-life scrapping. A published maintenance curve is flat through
    useful life and escalates afterward until replacement is cheaper, making
    retirement economic rather than enforced. Fallback-liquidated hulls are
    scrapped rather than recirculated. Depreciation and maintenance parameters are
    economic, not merely accounting, choices.
23. **Complete — Port capacity growth:** cities expand berths and warehouse
    capacity when utilization or queue waits stay above a threshold across a
    multi-quarter window, on a published trigger with an announced construction
    lead time. Triggering on utilization rather than volume makes capacity settle
    at a target occupancy. Berths may contract after sustained low utilization if
    unoccupied and uncommitted; warehouse capacity does not contract, since
    reducing it would raise every remaining tenant's renewal quote by operator
    action. Expansion is near-irreversible, so thresholds stay conservative.
    Player-funded port infrastructure is deferred with the facility rules.

### Tuning and implementation work

Numerical tuning includes grade thresholds and shelf lives, cargo and ship stats,
port capacities and handling speeds, warehouse block sizes and curve parameters,
reference values and band widths, the activity decay constant, owner-absence and
dormancy-warning intervals, departure accumulation windows and retry cooldowns,
the shipyard buyback fraction, the maintenance escalation curve,
invitation issuance rate and expiry, starter-package reduction ratio and floor,
the post-settlement storage grace period for won auction cargo, ship size classes
with per-berth-group and per-waterway limits, port capacity expansion thresholds,
measurement windows, lead times and increments, regional pricing responses and
local spread allowances, simulated bidder valuation spread and participation,
identity-linking prompt thresholds, interest and depreciation rates, and
provisional percentages and timers already recorded above. Keep those
configurable and validate with simulation and playtesting; each number need not
become a separate preference poll.

Configurable does not mean reversible. This document guarantees in several places
that terms already published to a player survive a later parameter change: locked
six-hour renewal quotes, disclosed grace deadlines, published auction schedules,
disclosed unloading-overrun rates, the liquidation surcharge, and the procurement
deposit percentage. In a world that never resets, that makes any parameter backing
an outstanding commitment effectively one-way. Port berth counts and warehouse
capacity can be raised but not lowered while leases are held, so size them
conservatively low at launch: adding capacity later is an announcement, while
removing it is a breach.

Where a parameter can only move one way, prefer building that movement into the
rules over leaving it to operator discretion. Port capacity is the worked example:
rather than operators enlarging congested ports by judgement, section 10 grows
them on a published trigger, measurement window, and construction lead time, so
the ratchet is a mechanic players can anticipate and plan against instead of an
intervention they discover. Apply the same preference to any future one-way
parameter. Parameters backing no outstanding promise, such as
spoilage rates, price-response curves, and rates on future loans, stay freely
adjustable in both directions. Record which of the two each constant is before
tuning it. Reference values, depreciation schedules, and the maintenance curve are
economic parameters under section 5 rather than presentation choices, whichever
category they fall into.

Technical design remains for persistence, authentication implementation,
transaction boundaries, idempotency, event ordering, recovery, bounded work and
history retention, and currency/time rounding. Resolve these against agreed
product behavior without treating routine engineering choices as product options.

Mines, factories, land, construction, production recipes, carriage for hire, and
player-funded port infrastructure remain later-phase work and are not included in
the 23 initial-game decision groups.
