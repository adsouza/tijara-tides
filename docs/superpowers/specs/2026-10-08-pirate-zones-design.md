# Pirate zones: priced risk on real sea lanes

Adds named danger zones where ships can be attacked, held and charged a ransom
or repair bill, with armed guards and voyage insurance as the player's levers.
Written 2026-10-08; revised the same day after review.

## Intent

Storms make voyages uncertain in time but never in money. Pirates add a risk
that players can see, price and buy down, located where it has a defensible
basis in the real world. Modern reporting supports the Red Sea, the Gulf of Aden
and Somali Basin, and the Malacca and Singapore Straits; history supports the
South China Sea, the Caribbean, the English Channel and the Barbary Coast.
Success means a player looking at a route through the Red Sea during an
announced campaign faces a real choice between paying for protection, accepting
the risk, or trading somewhere else.

Decisions taken during design:

| Question | Decision |
|---|---|
| Severity | Hold plus cash charge; risk is published and can be mitigated |
| Route choice | Not in this work; each port pair keeps its one route |
| Mitigation | Both armed guards (lower the odds) and insurance (lower the cost) |
| Threat over time | Base level per zone plus seeded, announced campaigns |
| What an attack takes | Time and cash; cargo is never touched |
| Storms | Suppress small-boat attacks; militia strikes ignore weather |

Out of scope: alternative routes (Suez or the Cape), seizing cargo, an owner
decision at the moment of attack, and losing ships. Each can follow later.

All durations below are world time (`clock_ms`), the unit the weather model and
voyages already use.

## The design promise changes

DESIGN.md section 10 says ships "do not randomly sink or lose cargo", and
section 9 says ships "neither sink nor fail catastrophically". Both remain true
for ships and cargo. Section 10 gains this paragraph in the same change that
first charges a ransom (phase 2):

> Some sea lanes carry a published risk of attack. An attacked ship is held for
> a period and its owner pays a ransom or repair bill; cargo stays aboard and
> continues to age. Armed guards lower the chance of attack and voyage insurance
> reimburses most of the charge. Zone threat, campaigns and protection prices
> are public before dispatch.

## Zones

Eight zones are polygons in the generator's source data
(`scripts/gen-game-data.py`), emitted into `priv/game/catalogue.json` under
`"piracy"`. Each has a kind, which fixes how an attack is described and
resolved. Phase 1 shipped the first five; phase 1b adds the Singapore Strait,
the English Channel and the Barbary Coast and lowers the Malacca Strait.

| Zone | Kind | Base chance per crossing | Guard effect | Basis |
|---|---|---|---|---|
| Red Sea and Bab-el-Mandeb | militia | 300 bps | 25% | Houthi strikes on shipping since 2023 |
| Gulf of Aden and Somali Basin | piracy | 400 bps | 90% | Somali hijackings, resurgent since 2023 |
| Singapore Strait | boarding | 600 bps | 60% | 80 of 137 incidents worldwide in 2025 (IMB annual report) |
| Malacca Strait | boarding | 150 bps | 60% | Far less reported activity than the Singapore Strait, where IMB places most incidents in these straits |
| South China Sea | fleet piracy | 200 bps | 60% | Ching Shih's confederation off Guangdong (1801–10) |
| Caribbean | piracy | 200 bps | 60% | Buccaneers, 17th–18th centuries |
| English Channel | piracy | 100 bps | 60% | Sea Beggars (1568–72) and Dunkirkers (c. 1583–1646) |
| Barbary Coast | piracy | 150 bps | 60% | Barbary corsairs, 16th–19th centuries |

The two new historical zones carry the lowest chances: their basis is the
weakest, and the English Channel is crossed by almost all North European trade.
Antwerp to Busan is one of 42 routes that cross seven zones, the most of any; at
base threat a 22-knot ship has about an 18% chance of at least one attack
(16–21% by class). Transpacific routes and Hamburg's North American routes cross
none; the rest of Hamburg's Atlantic trade and all Atlantic routes into Antwerp
and Rotterdam cross the English Channel.

Extents; polygons follow the sea where a box would cross much land:

| Zone | Extent |
|---|---|
| Red Sea | 32–43.5°E, 12.5–30°N, following the sea |
| Gulf of Aden | 43.5–60°E, 0–16°N |
| Singapore Strait | 104–104.7°E, 1.05–1.5°N, east of Singapore; the strait is too narrow for a box to avoid both shores |
| Malacca Strait | 95–103°E, 1.5–6.5°N, northwest of Singapore |
| South China Sea | 109–119°E, 6–21.5°N, the open sea up to the Guangdong approaches; west of 111°E it stops at 20°N, clear of the Leizhou Peninsula |
| Caribbean | 88–60°W, 10.5–22°N |
| English Channel | 5.8°W–1.75°E, mid-Channel from the Western Approaches through the Dover Strait, clear of the English and French coasts |
| Barbary Coast | 1°W–10°E, the lane off Algeria and Tunisia, its south edge just off the coast and its north edge clear of Spain |

**No port lies inside or near a zone.** The generator rejects a zone polygon
that contains any roster harbour coordinate or lies within 12.0 nautical miles
of one: the great-circle distance from the harbour coordinate to the nearest
point of any polygon edge, with edges straight in the longitude/latitude plane
as `Piracy.inside?/2` treats them. The generator enforces it with its haversine
`distance()` and `piracy_catalogue_test.exs` asserts it again. A port's
approaches are therefore never a danger zone and short local voyages stay safe:
Tangier–Valencia and Hong Kong–Guangzhou cross no zone. The South China Sea
extent is deliberately the open sea: a wider box (105–121°E, 3–21°N) would
contain Ho Chi Minh City (107.02°E, 10.51°N) and Manila (120.95°E, 14.59°N), and
its north edge stops 48 nautical miles short of Hong Kong. The Singapore Strait
is its own zone rather than an extension of the Malacca Strait because the
traffic lane passes about 8 nautical miles from Singapore's harbour, inside the
buffer, so no polygon can join the two around the port; the strait zone starts
14 nautical miles east of the harbour. A through voyage crosses both zones and
rolls for each, while a Singapore departure eastward crosses the strait but not
the Malacca Strait. Colón and the Pearl River ports also sit outside their
neighbouring zones. `piracy_catalogue_test.exs` asserts the per-zone route
counts that IMPLEMENTATION.md publishes.

Kind parameters, all provisional and catalogue-tunable:

| Kind | Mark | Hold | Charge (bps of class price) | Label | Storm suppresses |
|---|---|---|---|---|---|
| piracy | 🏴‍☠️ | 10 min | 400 ransom | Held by pirates | yes |
| fleet piracy | 🏴‍☠️ | 8 min | 300 ransom | Seized by a pirate fleet | yes |
| boarding | 🏴‍☠️ | 2 min | 50 robbery | Boarded and robbed | yes |
| militia | 💥 | 5 min | 200 repair bill | Repairing strike damage | no |

Holds compare with voyages of about 16 seconds to 67 minutes (65 to 12,032
nautical miles at 18 to 24 knots). A balanced freighter (class price $40,000)
pays a $1,600 piracy ransom. At 600 times physical speed a 22-knot ship covers
about 220 nautical miles per minute, so crossing the Red Sea takes about five
and a half minutes.

### Campaigns

Each zone rolls for a campaign once per campaign period from the public
catalogue seed, as storms do per sector. A campaign multiplies the zone's chance
and is announced before it starts. Campaigns are public by design: anyone who
reads the catalogue can foresee them, and the announcement is a convenience, not
a secret.

| Parameter | Provisional value |
|---|---|
| Period | 12 hours |
| Chance per period | 2,500 bps (Red Sea 4,000) |
| Duration | 3 hours, at a seeded offset within the period |
| Warning | 30 minutes before the start |
| Multiplier | ×4 |

Each zone carries a short list of campaign names chosen by a seeded index, for
example the Red Flag Fleet in the South China Sea after Ching Shih's
confederation. Phase 1b adds Horsburgh raiders and Bintan boarders for the
Singapore Strait, Dunkirkers and Sea Beggars for the English Channel, and
Algiers corsairs and Barbarossa's fleet for the Barbary Coast. The model is
validated when the catalogue is loaded: a warning plus duration that does not
fit within the period, a chance outside 0..10,000 basis points, a polygon with
fewer than three vertices, or a missing salt in production fails startup and
never reaches a tick.

### Visibility

Zone outlines, kinds, current chances, announced campaigns (with countdown) and
active campaigns (with name and time remaining) are public. Nothing about a
ship's protection, its charges or its manifest is public. A held ship's status
line is public in the same way a storm wait is.

## Attacks during a voyage

### Crossings

At departure the ship's path is partitioned at zone boundaries in the manner of
`Weather.segments/1`, producing an ordered list of pending crossings, each
`{index, zone, from_fraction, attack_fraction, into_fraction}`. The attack
fraction is seeded between `from_fraction` and `into_fraction` from the salt,
ship id, `depart_ms` and index. The list is snapshotted in `ships.piracy`
together with the protection bought. Catalogue changes never alter a voyage
underway.

**Legacy voyages.** Ships already sailing when phase 2 deploys have no snapshot.
They are never attacked and carry no protection. A diversion of a legacy voyage
creates a snapshot for the new path from the diversion point.

**Diversions.** `Ship.reroute` replaces the path and sets `depart_ms` to now, so
fractions on the old path mean nothing on the new one. A reroute therefore:

1. Keeps resolved crossings as fraction-free records `{index, zone, outcome,
   charge, recovery}`.
2. Drops pending crossings of the old path.
3. Partitions the new path and appends its crossings with indices continuing
   after the old count.
4. Marks a new crossing as resolved with outcome `continued` if it starts at the
   diversion point (`from_fraction` 0) and a resolved record of that zone
   exists. A diversion can therefore never re-roll a zone the ship is still
   crossing. A `continued` crossing carries no guard fee and no premium term.

Incidents already recorded keep their absolute times (see The hold).

### The roll

Each pending crossing resolves once, when the ship's motion on the shared
timeline reaches its attack fraction. The attack time is the world time at which
that happens on the forecast. Chance is computed in integer basis points in this
order, so the dispatch quote and the tick agree exactly:

```
bps = base_bps
bps = bps * multiplier                      if campaign_active?(zone, attack_time)
bps = div(bps * (100 - guard_pct), 100)     if the voyage carries guards
bps = div(bps * 22, class_speed)            for small-boat kinds; militia skip this
bps = min(bps, 10_000)
hit = phash2({salt, ship_id, depart_ms, index}, 10_000) < bps
```

`Piracy.campaign_active?(zone, at_ms, model)` is the pure seeded model; the roll
and the quote both call it. The `piracy_campaigns` rows are a public projection
of the current moment, read only by queries, so a large tick that passes the end
of a campaign still applies it to an attack that happened before the end. The
class factor makes a slow bulk carrier (18 knots) easier to board than a fast
reefer (24 knots). The salt is set in `config/runtime.exs` under `:tijara_tides,
:piracy` and injected into the loaded catalogue by `GameCatalogue`, as weather
overrides already are. It is never written to `priv/game/catalogue.json`; a
generated-file test asserts that. A public salt would let players precompute
outcomes and time departures to dodge them; storms can use the public seed
because they are announced.

Resolution is deterministic across replays, restarts and tick sizes. Every input
either precedes the attack time or is fixed at departure. Storms that started
before the attack time are already announced by the cutoff `now`. Incidents
carry absolute times.

### Storm suppression

For small-boat kinds, the attack is called off when any storm window over the
attack point's weather sector overlaps the interval from the ship's entry into
the crossing to the attack time. The sector is that of the snapshotted weather
segment (`ships.weather["segments"]`) containing the attack fraction. Windows
come from the snapshotted weather model, filtered by the same `first_slot` and
`since_ms` rules `cross/7` applies, so suppression never counts a storm the
forecast ignored. Entry is the forecast time of `from_fraction`; for a crossing
starting at fraction 0 it is `depart_ms`. The crossing is then recorded with
outcome `suppressed` ("rough seas kept the raiders away"). Checking the interval
rather than the instant matters: a storm pauses the ship, so the ship reaches
its attack point either before a storm or after it, never during one. Militia
strikes ignore weather. The check reads `Weather.window/3` for the sector's
slots in that interval and adds no state.

### The hold

A hit becomes an **incident** stored on the ship with absolute `starts_ms =
max(attack_time, last_cost_ms)` and `until_ms = starts_ms + hold`. The attack
time already lies after `last_cost_ms`, because `VoyageHazards` runs before
fleet settlement advances it, so the clamp is defensive only.

Incidents join the storm pauses in **one pause timeline**, built by one pure
function, `Ship.timeline(ship, route, now, elapsed, speedup, catalogue,
incidents)`. It derives the inputs `Ship.apply_weather` derives today
(`retime_voyage`, the voyage path, the snapshotted model, `duration/3`,
`since_ms`, cached segments). `apply_weather` and the `VoyageHazards` loop both
call it; nothing else calls `Weather.forecast` for a sailing ship, so the loop's
attack times and the stored holds can never disagree. `Weather.forecast` takes
incidents through an options map; the existing positional arguments stay. Its
segment walk inserts each incident when the cursor reaches the incident's
fraction, at `max(cursor, starts_ms)`, the way `cross/7` places storms. Storms
after an attack are therefore timed against the delayed position, and a storm
falling inside an incident adds no further pause. The skip shortcut (no active
storms, or before the first slot) must not drop incidents. Storm holds and
incident holds come out in the same `holds` list, each tagged with its source,
so `motion/4`, `paused/3`, `current/2` and their movement readers (navigation,
fuel, crew, freshness, map markers, ETAs) need no change. Display readers do:
`GameQueries.weather_wait/2` returns the hold's source tag so the inspector can
show the mark, kind label and zone. Because incidents only start at or after
`last_cost_ms`, the existing "Weather cannot rewrite settled voyage movement"
check stays unreachable.

A held ship accepts the same commands as a storm-held ship, except diversion,
which is refused with a distinct error (`:held_by_pirates`) until the hold ends.
That check is its own clause ahead of the `with` in `Fleet.reroute`, which
otherwise maps every failure to `:reroute_invalid`. Holds may extend a voyage
beyond the normal duration ceiling, as storms already do.

## Money

All amounts are integers in cents, computed from basis points of the ship class
price and never from the manifest. New ledger codes join `@expenses` in both
`CompanyFinance` and `Reporting`:

- `piracy_guard_expense`
- `piracy_premium_expense`
- `piracy_charge_expense`

All three report as operating costs.

**Armed guards** are chosen at dispatch. The fee is 15 bps of class price per
zone crossed (provisional; $60 per zone for a balanced freighter). It is
expensed at departure like canal fees (`{"cash_available", -fee}`,
`{"piracy_guard_expense", fee}`), after the same affordability check.

**Insurance** is chosen at dispatch and covers the voyage. Its premium is:

```
expected = Σ over crossings div(quoted_bps * charge * 80, 10_000 * 100)
premium  = max(2_500, div(expected * 140, 100))
```

The premium is expensed at departure to `piracy_premium_expense`. Insurance is
not offered on a route that crosses no zone. The quoted chance applies the roll
formula to each crossing's forecast attack time. The campaign term there counts
only campaigns active or announced at dispatch whose window covers that attack
time. The premium deliberately uses public information only: a campaign
announced after dispatch is the insurer's risk, and the calibration script
accounts for it. Insurance covers money, not time.

**Charges.** At the attack the company is charged the kind's share of class
price, and an insured incident is reimbursed `recovery = div(charge * 80, 100)`
(otherwise 0). Both post as one event, mirroring `ship_operations`:

```
net  = charge - recovery
paid = min(net, cash - reserved)
post {piracy_charge_expense, charge}, {piracy_charge_expense, -recovery},
     {cash_available, -paid}, {payables, -(net - paid)}
operating_bill(company, net - paid, now)
```

The charge never spends reserved fuel cash and never raises, and an insured
company with no free cash owes only the deductible. A negative expense entry
raises profit (`company_finance.ex:42`) and adds its signed amount to the
operating report line, so reports show the net loss. The incident stores both
amounts.

**Receivership.** Crossings of ships whose company has `bankruptcy_ms` set (the
test `Fleet.advance` and `Services.Estates` already use) resolve with outcome
`exempt`. Estates are never charged or reimbursed.

**Diversions.** A reroute adds guard fees for newly crossed zones, excluding
`continued` crossings, (if the voyage has guards) and premium for new crossings
(if insured), through the same quote. Nothing is refunded for zones no longer
crossed. The existing `reroute_funds` admission covers these amounts.

**Economy.** Guards, premiums and charges leave the economy; recoveries return
part of it. With a 1.4 loading the insurance flows are a net drain in
expectation.

**Calibration rule**, checked with a script in phase 3: at base threat, guards
should cost about what the attacks they prevent cost (including hold time at
idle crew rates); during a campaign, protection should clearly pay. If the
provisional numbers miss, change the numbers, not the rule.

## What players see

The Jolly Roger 🏴‍☠️ marks piracy, fleet piracy and boarding wherever a zone,
crossing, hold or notice appears; 💥 marks militia strikes. The flag is a single
emoji sequence (black flag, zero-width joiner, skull and crossbones). It sits
beside the text label, never in place of it, so it stays readable where the
sequence renders as two glyphs and for screen readers.

- **Map.** Zone polygons shaded normal, elevated or campaign, with the kind's
  mark. Announced campaigns show a countdown; active ones show their name and
  time remaining.
- **Dispatch preview.** A protection block lists each crossing with its mark,
  quoted chance and the charge at stake, plus Guards and Insurance toggles with
  their prices. The Insurance toggle is absent when the route crosses no zone.
  Totals join the affordability check. The ETA includes only actual incidents,
  never possible ones.
- **Ship inspector (public).** The mark, kind label, zone and countdown while
  held.
- **Owner fleet controls.** Protection bought, each crossing's outcome, any
  charge and recovery.
- **Notices.** One structured notice per incident (ship, zone, kind, hold,
  charge, recovery), keyed `"piracy:" <> ship_id <> ":" <> index`. Weather
  notices keep their own key. `VoyageHazards` skips the weather notice for a
  ship in a tick where it recorded an incident for that ship, because the
  incident notice already reports the delay. A campaign announcement notifies
  each owner once per sailing ship with a pending crossing in that zone, keyed
  `"campaign:" <> window_id <> ":" <> ship_id` and written only when absent.
- **Localization.** All messages in English and Arabic via `mix gettext.extract`
  (never merge), checked by `scripts/check-gettext-catalogues.py`.

### Automation

Route plans gain a Protection setting: none, guards, insurance, or both,
defaulting to none. `DepartureFunding.requirement/3`,
`Trading.voyage_requirement` and the collect-visit check in
`Services.AutomatedVisits` add protection costs from the shared quote; trade and
planning queries derive the requirement from those same functions. A departure
request records the protection choice it was created for, and `Fleet.sail` gains
a protection argument (all four call sites in `DepartureFunding`, plus
`Commands`). A changed setting applies to the next request.

The premium can change while a request waits, because a campaign announced in
the meantime raises it. Each attempt therefore recomputes `required` from the
current quote and updates the row, clamping `accumulated` to the new `required`
and releasing any excess, as fuel is already requoted at attempt time. A request
can never be stranded below a stale requirement.

## Architecture

| Unit | Responsibility |
|---|---|
| `Domain.Piracy` (pure) | Zone and campaign model, load-time validation, path partition, attack fraction, chance, roll, storm suppression, protection quote |
| `Domain.Weather` | `forecast` accepts incidents in an options map; the holds list carries both sources |
| `PiracyWorld` (root) | Owns `piracy_campaigns`: announced and active campaign rows per zone, refreshed like `WeatherWorld`, including in `Simulation.initialize` |
| `ShipWorld` (root) | Owns `ships.piracy`; transitions `snapshot_piracy` (departure, reroute) and `record_crossing` (outcome and incident) |
| `CompanyFinanceWorld` (root) | Posts charges, recoveries and bills it is asked to post |
| `Fleet` | Initiates protection payments in dispatch and reroute from the shared quote, as it does canal fees |
| `Services.VoyageHazards` | Replaces `Services.WeatherDelays` at the same point in `Simulation` |

`Services.VoyageHazards.advance/4` refreshes `WeatherWorld` and `PiracyWorld`,
then handles each sailing ship in id order:

1. Build the timeline with `Ship.timeline/7` (cutoff `now`).
2. Take the first pending crossing in path order whose attack time is at or
   before `now`, if any.
3. Resolve it: exempt, suppressed, missed or hit. Record the outcome and any
   incident.
4. On a hit, post the charge and recovery, then **re-forecast before evaluating
   the next crossing**, because the hold delays every later attack time.
5. Repeat until no pending crossing is due.
6. Apply the final timeline and send at most one incident notice per incident,
   plus the weather notice when no incident occurred.

Storms and attacks resolve in one walk because each shifts when the ship meets
the other. Roots never call `Services.*`.

### Persistence

One migration adds `ships.piracy` (JSON: protection, pending crossings, resolved
records, incidents) and the `piracy_campaigns` table. Row codecs write complete
rows. `PiracyWorld` joins the table-ownership boundary tests in `test/docs/`. On
arrival the ship's `piracy` snapshot is cleared with its weather snapshot.

### Tick safety

Nothing reachable from the tick raises:

- The model and salt are validated at load.
- Amounts are integers computed from basis points.
- Charges split into paid and payable before posting.
- Incident starts never precede `last_cost_ms`.
- Receivership ships are exempt rather than charged.

`TijaraTides.SettledCheck` gains these invariants. The first three need the
states before and after plus the transition's `state.journal`, so they form a
new clause in `assert_settled!/4`; the fourth fits the per-state `violations/2`
list.

- Every incident added in a transition matches exactly one
  `piracy_charge_expense` debit in that transition's `state.journal` for the
  stored charge.
- For insured incidents, the incident matches exactly one recovery credit for
  the stored recovery.
- A ship whose current hold is an incident keeps the same `destination`,
  `voyage_path` and `depart_ms` across any command.
- Every crossing index appears at most once among resolved records.

## Testing

- **Pure:** partition on real routes, including zone entry and exit within one
  leg; the generator's no-port-inside rule; attack-fraction and roll determinism
  across replay, restart and different tick sizes; integer chance arithmetic;
  class factor; storm suppression over the crossing interval for small-boat
  kinds and not for militia; a storm overlapping an incident; the settled-time
  clamp; a second crossing timed after the first incident's hold; the forecast
  skip shortcut keeping incidents.
- **Catalogue (phase 1b):** the harbour buffer with synthetic polygons whose
  nearest edge lies 11.9 nautical miles from a harbour (rejected) and 12.1
  (accepted), sampling each edge at most every 0.01° in the generator and the
  test alike; the exact per-zone route counts; lanes as
  well as ports: Tangier–Valencia and Hong Kong–Guangzhou cross no zone,
  Tangier–Athens crosses the Barbary Coast, Singapore–Busan crosses the
  Singapore Strait but not the Malacca Strait, and Antwerp–Busan crosses seven
  zones.
- **Automation:** a campaign announced while a request waits raises its
  `required` on the next attempt and the request still departs once funded.
- **Diversion:** resolved records survive; `continued` crossings carry no fee; a
  diversion inside a resolved zone cannot re-roll it; indices continue; a legacy
  voyage gains a snapshot only on diversion.
- **Contracts:** the offered protection quote is accepted and one cent more is
  refused, for dispatch, reroute and automated funding
  (`test/tijara_tides/use_cases/*_offers_test.exs`).
- **Finance:** uninsured and insured incidents; a charge with zero available
  cash becoming an operating bill without raising; reserved fuel cash untouched;
  receivership exemption; report categories.
- **Catalogue:** the tracked `catalogue.json` contains no salt.
- **Database:** round trip of `ships.piracy` and `piracy_campaigns`.
- **LiveView:** protection toggles, the 🏴‍☠️ and 💥 marks beside their labels,
  held status in the public inspector, notice keys; the Guards and Insurance
  fields join the form-contract allowlist and the CI control sweep reaches them.
- Each new guard, invariant and contract test is broken once to confirm a test
  fails.

## Delivery

Five phases, each shippable on its own and each with its documentation updates
(IMPLEMENTATION.md, architecture.md, generated documents) in the same change:

- **Phase 1: Zones and campaigns.** Polygons, generator rules and route counts,
  `PiracyWorld`, map shading and marks, countdowns. No attacks.
- **Phase 1b: More zones.** The Singapore Strait, English Channel and Barbary
  Coast, the lowered Malacca Strait chance, the 12-nautical-mile harbour
  buffer, and their names in English and Arabic. Delivered before phase 2
  because counts, tests and docs are cheaper to change before attacks exist.
  It needs no migration: `game_piracy_campaigns` is keyed by world and zone id,
  `PiracyWorld.refresh/2` adds rows for new zones on the next tick, base
  chances are not persisted, and existing campaign windows depend only on the
  seed, zone id, slot and campaign chance, all unchanged. A deployed `:piracy`
  override of `"zones"` would replace all eight, since the merge is shallow;
  none is configured today.
- **Phase 2: Attacks.** Crossings snapshot, roll, storm suppression, shared
  timeline, charges, operating bills, notices, public held status,
  `VoyageHazards`, the DESIGN.md amendment.
- **Phase 3: Protection.** Guards, insurance, dispatch block, reroute top-ups,
  calibration script.
- **Phase 4: Automation.** Route-plan Protection setting and automated funding.

## Tuning left open

Every number marked provisional above: base chances, guard effects, hold
durations, charge shares, guard fee, insurance loading and deductible, campaign
period, chance, duration, warning and multiplier. All live in the catalogue
model or runtime config and can change without migrations.

## Sources

- IMB Piracy Reporting Centre, *Piracy and Armed Robbery Against Ships, 2025
  annual report*: 137 incidents worldwide, 80 in the Singapore Strait, 21 in
  the Gulf of Guinea and a small number off the Somali coast.
  [ICC summary](https://iccwbo.org/news-publications/report/global-maritime-piracy-and-armed-robbery-increased-in-2025/)
