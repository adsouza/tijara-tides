#!/usr/bin/env python3
"""Regenerate docs/ports.md, the launch port roster, from the data below.

The roster's coverage table is derived from its trade-role tables, so the two
are generated together from one source rather than maintained side by side.
Invariants are asserted here at generation time and re-checked independently by
test/docs/ports_roster_test.exs, which parses the committed markdown. CI
regenerates and runs `git diff --exit-code docs/ports.md`, so never hand-edit
the document: the next run overwrites it and CI fails.

Adding a good
-------------
1. Add its name to the right list in CATEGORIES. Column order in the generated
   tables follows that order.
2. Give every port in M a role at the matching column position. Positions are
   silent about mistakes, so count carefully, or insert with a dict keyed by
   port name as the vegetable oil change did.
3. Update REEXPORTS for merchant-supplied goods; preserve independent buy/sell weights.
   Bump the expected count in test/docs/ports_roster_test.exs (`parsed.goods`).
4. Update the good-count claims in docs/DESIGN.md: the catalogue table and
   count sentence in section 6, the recipe sentence in section 5, and decision
   group 20. If the good needs liquid or refrigerated capacity, say so in
   section 6 and section 11 too.
5. Regenerate. Coverage minimums are enforced below: bulk commodities need four
   exporters and five importers, everything else three and four.

Adding a port
-------------
1. One PORTS entry: harbor, identity sentences, physical tiers.
2. One row in M.
3. One entry in REGIONS, which sets table order. Omitting it fails the
   ORDER/PORTS assertion below rather than emitting a partial document.
4. Add it to CLUSTERS if it shares a catchment with existing ports. Clustered
   ports must differ in at least half their trade roles.
5. Bump the expected port counts in test/docs/ports_roster_test.exs
   (`parsed.roles` and `parsed.tiers`), and the cluster count if CLUSTERS grew.
6. Add it to the roster list in docs/DESIGN.md section 4, which also requires
   the user's approval for any addition, and to the harbor table if the city
   and harbor names differ.
7. Regenerate.

Either change must leave every port both importing and exporting something, or
it becomes a dead end for round trips. The test states the full invariant list.
"""
import io
import textwrap
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

CATEGORIES = [
    ("Bulk commodities", ["Iron ore", "Grain", "Lumber", "Crude oil", "Refined fuel",
                         "Vegetable oil"]),
    ("Luxury items", ["Whisky", "Jewelry", "Designer clothing"]),
    ("Industrial machinery", ["Turbines", "Construction equipment",
                              "Agricultural machinery"]),
    ("Mass consumer products", ["Electronics", "Appliances",
                                "Everyday clothing", "Spices"]),
    ("Scrap", ["Scrap aluminium", "Copper scrap", "Recovered plastics"]),
    ("Perishables", ["Fruit", "Seafood", "Meat"]),
]

CLUSTERS = {
    "Pearl River Delta": ["Hong Kong", "Shenzhen", "Guangzhou"],
    "Northern Frangistan": ["Rotterdam", "Antwerp", "Hamburg"],
    "Strait of Hormuz": ["Dubai", "Abu Dhabi"],
}

# port: (harbor, identity, tiers)
# tiers = berths, ordinary, reefer, liquid, handling speed, handling cost, max size
PORTS = {
"Shanghai": ("Waigaoqiao and Yangshan",
 "China's largest gateway, serving the Yangtze Delta's steel, machinery "
 "and electronics industries. Ore and crude in, finished manufactures out, "
 "with a wealthy consumer market of its own.",
 ("high","high","high","high","fast","med","split")),
"Singapore": ("Singapore",
 "Transshipment and refining hub with almost no primary hinterland. Buys "
 "crude to sell refined fuel, re-exports spirits across the region, and "
 "imports nearly all of its food.",
 ("high","high","med","high","fast","high","any")),
"Shenzhen": ("Yantian",
 "Electronics manufacturing capital of the Pearl River Delta. Draws copper "
 "and components in, ships finished devices out.",
 ("high","high","med","low","fast","med","any")),
"Guangzhou": ("Nansha",
 "The delta's heavy and household manufacturing arm: appliances, apparel, "
 "construction and agricultural machinery, and a large grain-consuming "
 "population.",
 ("med","high","med","med","med","low","any")),
"Hong Kong": ("Hong Kong",
 "Transshipment, finance and luxury retail with no manufacturing base. The "
 "roster's largest re-exporter of jewelry and rare whisky, and the centre "
 "of its collector auction trade, importing essentially all of its food.",
 ("high","med","high","low","fast","high","any")),
"Busan": ("Busan",
 "Korea's industrial gateway: steel, shipbuilding, heavy turbines and "
 "consumer electronics, fed by imported ore and crude. Exports refined "
 "fuel and the catch of a large distant-water fishing fleet.",
 ("high","high","high","med","fast","med","any")),
"Tokyo": ("Tokyo",
 "High-value Japanese manufacturing — construction and agricultural "
 "machinery, turbines, electronics — alongside the roster's foremost "
 "whisky distilling and the world's largest appetite for imported seafood.",
 ("high","med","high","med","fast","high","any")),
"Ho Chi Minh City": ("Saigon and Cai Mep",
 "Vietnam's export engine for apparel, electronics, rice, fruit, pepper "
 "and farmed seafood. Takes in refined fuel and recovered plastics for "
 "processing.",
 ("med","med","med","med","med","low","split")),
"Jakarta": ("Tanjung Priok",
 "Indonesian resource exporter and fast-growing consumer market, importing "
 "grain and fuel while shipping ore, palm oil, the nutmeg and cloves of "
 "the original Spice Islands, apparel and seafood. Its regional sawmills "
 "also supply lumber.",
 ("med","med","low","med","slow","low","any")),
"Manila": ("Manila",
 "Philippine semiconductor assembly, nickel and iron ore mining, and "
 "tropical agriculture. The roster's leading fruit, tuna and coconut oil "
 "exporter, dependent on imported grain, fuel and meat.",
 ("low","low","med","low","slow","low","any")),
"Colombo": ("Colombo",
 "South Asian transshipment point and the roster's cinnamon source, "
 "exporting spices, apparel, gemstones and seafood. Small hinterland, so "
 "most bulk arrives rather than departs.",
 ("med","med","low","low","med","low","any")),
"Mumbai": ("Jawaharlal Nehru / Nhava Sheva",
 "India's largest container gateway: ore, refined fuel, tractors, apparel "
 "and spices out, crude in, and the roster's dominant cut-gemstone and "
 "jewelry exporter. A heavy scrap buyer.",
 ("med","med","low","med","slow","low","any")),
"Dubai": ("Jebel Ali",
 "Re-export hub for consumer goods and gold across the Gulf and East "
 "Africa, with sustained construction demand and no food production.",
 ("high","high","med","med","fast","med","any")),
"Abu Dhabi": ("Khalifa Port",
 "Crude and refined fuel exporter with large aluminium smelting that "
 "consumes imported scrap. Buys power-generation turbines and all of its "
 "food.",
 ("med","med","low","high","fast","med","any")),
"Rotterdam": ("Rotterdam",
 "Europe's largest port and its oil gateway, feeding Rhine-valley steel "
 "and engineering. Exports refined fuel, turbines and scrap and lands "
 "enormous volumes of fruit.",
 ("high","high","med","high","fast","high","any")),
"Antwerp": ("Antwerp",
 "Chemicals, refining and Europe's diamond trade, with major reefer "
 "capacity and a construction-machinery export stream. Ships refined "
 "products and recovered plastics outbound, and its inland catchment "
 "reaches Italian and French fashion houses.",
 ("med","high","high","high","fast","high","any")),
"Hamburg": ("Hamburg",
 "German and Central European machinery export — turbines, construction "
 "and agricultural equipment — plus grain, meat and scrap aluminium "
 "outbound to Asia. Europe's largest copper smelter sits here and consumes "
 "imported copper scrap. Its inland catchment also carries Central "
 "European fashion houses and sawmill lumber.",
 ("high","high","med","med","fast","high","any")),
"Valencia": ("Valencia",
 "Spanish Mediterranean exporter of citrus, pork, appliances and apparel, "
 "and of construction and agricultural machinery, with strong reefer "
 "capacity and moderate costs.",
 ("med","med","high","low","fast","med","any")),
"Athens": ("Piraeus",
 "Greek refining, ore mining and aluminium production alongside "
 "Mediterranean transshipment. Exports fuel, ore, metal scrap and fruit; "
 "imports grain and meat.",
 ("med","med","low","med","fast","med","any")),
"Tangier": ("Tanger Med",
 "Low-cost North African transshipment and light manufacturing: apparel, "
 "electronics assembly, citrus and sardines, against imported grain and "
 "fuel.",
 ("med","med","low","low","fast","low","any")),
"New York City": ("Port Newark–Elizabeth",
 "The US Northeast's consumer gateway and a luxury market in its own "
 "right, exporting scrap, meat and American whiskey while importing "
 "finished goods and fuel.",
 ("med","med","med","med","med","high","any")),
"Los Angeles": ("San Pedro Bay",
 "The largest US import gateway for consumer goods, balanced by "
 "Californian produce, beef and the roster's heaviest scrap export. "
 "Congestion-prone and expensive.",
 ("high","high","high","med","med","high","any")),
"Houston": ("Bayport",
 "US Gulf energy and agriculture: crude, refined fuel, grain, beef, heavy "
 "machinery, Kentucky whiskey and the roster's broadest scrap and "
 "recovered-plastics export. Regional sawmills add lumber to its outbound "
 "cargoes. Channel draft excludes the largest ships.",
 ("med","med","low","high","med","med","capped")),
"Colón": ("Manzanillo",
 "Canal-side transshipment and the Colón Free Zone's re-export trade into "
 "Latin America, plus Central American bananas.",
 ("med","high","med","low","fast","low","any")),
"São Paulo": ("Santos",
 "Brazil's agricultural and mineral outlet: soy and soy oil, iron ore, "
 "crude, citrus and the roster's largest meat export, against imported "
 "fuel and manufactures. Regional sawmills supply lumber for export.",
 ("med","med","high","med","med","med","any")),
}

E2, E1, I1, I2, X = "++exp", "+exp", "+imp", "++imp", "—"

M = {
"Shanghai":         [I2,I1,I2,I2,E1,I2,I2,I2,I2,E2,E2,E1,E2,E2,E1,I2,I1,I2,X ,I1,E1,I2],
"Singapore":        [X ,I1,I1,I2,E2,I1,E1,I1,I2,I1,I1,X ,E1,I1,I1,I1,E1,E1,X ,I2,I1,I2],
"Shenzhen":         [X ,I1,I1,X ,I1,I1,X ,X ,X ,X ,E1,X ,E2,E1,E1,I1,I1,I2,X ,I1,I1,I1],
"Guangzhou":        [I1,I2,I2,I1,I1,I1,I1,X ,X ,E1,E2,E2,E1,E2,E2,E1,I1,I1,I1,I1,E1,I1],
"Hong Kong":        [X ,I1,X,X ,I1,I1,E2,E2,I2,X ,I1,X ,I1,I1,I1,I1,E1,E1,E1,I2,I2,I2],
"Busan":            [I2,I2,I1,I2,E2,I1,I1,I1,I1,E2,E1,X ,E2,E2,I1,I1,I2,I1,I1,I1,E2,I2],
"Tokyo":            [I2,I2,I2,I2,I1,I1,E2,I2,I2,E2,E2,E2,E2,E2,I2,I1,E2,E1,E1,I2,I2,I2],
"Ho Chi Minh City": [I1,E1,I2,E1,I2,E1,X ,X ,X ,I1,I1,I1,E2,E1,E2,E2,I1,I1,I2,E2,E2,I1],
"Jakarta":          [E2,I2,E2,I1,I2,E2,X ,X ,X ,I1,I2,I1,I1,I1,E2,E2,I1,I1,I2,E1,E2,I2],
"Manila":           [E1,I2,I1,I1,I2,E2,X ,X ,X ,I1,I2,I1,E2,I1,E1,I1,E1,E1,I1,E2,E2,I2],
"Colombo":          [X ,I2,I1,I1,I2,E1,X ,E1,X ,I1,I1,I1,I1,I1,E2,E2,E1,E1,X ,E1,E2,I1],
"Mumbai":           [E2,E1,I2,I2,E2,I2,I1,E2,I1,E1,I1,E2,I2,I1,E2,E2,I2,I2,I2,E1,E2,E1],
"Dubai":            [X ,I2,I2,E1,I1,I2,I1,E2,I2,I1,I2,X ,I2,I2,I2,E1,I2,I1,X ,I2,I1,I2],
"Abu Dhabi":        [I1,I2,I1,E2,E2,I1,X ,X ,X ,I2,I2,X ,I1,I1,I1,I1,I2,I1,X ,I2,I1,I2],
"Rotterdam":        [I2,I2,I2,I2,E2,I2,X ,X ,X ,E2,E1,E2,I1,I1,I2,I2,E2,E2,E2,I2,I1,E1],
"Antwerp":          [I1,I2,I1,I2,E1,I1,X ,E2,E1,E1,E2,E1,I1,I2,I1,I1,E1,E1,E2,I2,I1,E1],
"Hamburg":          [I1,E2,E2,I1,I1,I1,X ,X ,E1,E2,E2,E2,I2,E1,I1,I2,E2,I2,E2,I1,I1,E2],
"Valencia":         [I1,I1,I1,I1,I1,E1,X ,X ,E1,I1,E2,E2,I1,E2,E2,I1,E1,E1,E1,E2,E1,E2],
"Athens":           [E1,I2,I1,I2,E2,E1,X ,X ,X ,I1,I1,I1,I1,I1,I1,I1,E2,E1,E1,E2,E1,I2],
"Tangier":          [X ,I2,I1,I1,I2,I1,X ,X ,E1,I1,I1,I1,E1,I1,E2,E1,I1,I1,I1,E2,E2,I1],
"New York City":    [X ,E1,X,X ,I2,I1,E1,I2,I2,I1,I1,X ,I2,I2,I2,I2,E2,E2,E2,I2,I1,E1],
"Los Angeles":      [X ,E1,I1,I1,I1,I1,I2,I2,I2,I1,I1,E1,I2,I2,I2,I2,E2,E2,E2,E2,I1,E2],
"Houston":          [I1,E2,E1,E2,E2,E1,E1,X ,X ,E2,E2,E2,I1,I1,I1,I1,E2,E2,E2,I1,I1,E2],
"Colón":            [X ,I1,I1,I1,I2,I1,X ,X ,E2,I1,I1,I1,I2,E2,E2,I1,E1,E1,X ,E2,E1,I1],
"São Paulo":        [E2,E2,E2,E2,I2,E2,I1,I1,I1,I1,I1,I1,I2,I2,I1,I1,I1,I1,I1,E2,I1,E2],
}

REGIONS = [
 ("East Asia", ["Shanghai","Busan","Tokyo","Hong Kong","Shenzhen","Guangzhou"]),
 ("Southeast Asia", ["Singapore","Ho Chi Minh City","Jakarta","Manila"]),
 ("South Asia", ["Colombo","Mumbai"]),
 ("The Gulf", ["Dubai","Abu Dhabi"]),
 ("Northern Frangistan", ["Rotterdam","Antwerp","Hamburg"]),
 ("Mediterranean and North Africa", ["Valencia","Athens","Tangier"]),
 ("North America", ["New York City","Los Angeles","Houston"]),
 ("Latin America", ["Colón","São Paulo"]),
]
ORDER = [p for _, ps in REGIONS for p in ps]
assert sorted(ORDER) == sorted(PORTS), set(ORDER) ^ set(PORTS)

GOODS = [g for _, gs in CATEGORIES for g in gs]
# Merchant supply is resale, never production. Values are independent buy weights;
# existing export weights in M remain the selling weights.
REEXPORTS = {
    "Hong Kong": {"Whisky": I2, "Jewelry": I2},
    "Singapore": {"Whisky": I1, "Electronics": I1},
    "Dubai": {"Jewelry": I2, "Spices": I1},
    "Guangzhou": {"Spices": I1},
    "Tangier": {"Spices": I1},
    "Colón": {"Designer clothing": I2, "Appliances": I2,
              "Everyday clothing": I2},
}
for port, goods in REEXPORTS.items():
    assert port in PORTS
    for good, buying in goods.items():
        i = GOODS.index(good)
        selling = M[port][i]
        assert selling in (E1, E2) and buying in (I1, I2), (port, good)
        M[port][i] = selling + "/" + buying

SIZE = {"any": "any", "capped": "≤ large", "split": "split"}
W = 80
def para(t): return textwrap.fill(" ".join(t.split()), width=W,
                                  break_long_words=False, break_on_hyphens=False)

o = []
o.append("# Tijara Tides — Launch Port Roster\n")
o.append(para("""
Economic identities and physical character for the 25 launch ports. This
document supplies the data that the rules in [the game design](DESIGN.md) reserve
space for: section 4 asks for city economic identities, section 5 leaves
city-level supply and demand open and requires regional catchments to share
price movement, and section 6 fixes the 22-good catalogue used here."""))
o.append("")
o.append(para("""
Authoritative here: which ports supply and demand which goods and at what
relative weight, which ports share a catchment, and each port's physical
capacity and cost relative to the others. Not here: numeric values, which remain
tuning parameters recorded in the design; production recipes and factory
inventory quantities, which the design defers; and the composition of the roster
itself, which section 4 fixes and only the user may change."""))
o.append("")
o.append(para("""
This file is generated by `scripts/gen-ports-roster.py`, which holds the roster
data. Edit the data there and regenerate rather than editing this file, or the
next run will overwrite the change. `test/docs/ports_roster_test.exs` re-derives
the invariants at the end from the tables here and fails if any is broken, so it
catches a drifted edit either way."""))
o.append("")
o.append(para("""
Adjusting a role or a tier is balancing work and does not need a design
decision. Changing what the roles mean, or the invariants at the end, is a
change to the design and belongs in DESIGN.md."""))
o.append("")

o.append("## Catchments and clusters\n")
o.append(para("""
Ports sharing a catchment draw on substantially the same hinterland, so section 5
requires their supply and demand to move together and their simulated quote
spreads to stay near the cost of moving goods between them. Cluster membership
is therefore data this document must state rather than leave implied."""))
o.append("")
for name, members in CLUSTERS.items():
    o.append("- **%s:** %s" % (name, ", ".join(members)))
o.append("")
o.append(para("""
Every other port stands alone in its own catchment. Correlated prices make
specialization the only thing distinguishing ports inside a cluster, so their
identities below deliberately diverge, and their physical tiers differ as well."""))
o.append("")

o.append("## Port identities\n")
o.append(para("""
Each identity characterizes a port: its real economic base and what that
means for the goods moving through it. They are orientation, not
enumeration, and no sentence lists every good. Where an identity and
the trade role tables below could be read differently, the tables are
authoritative."""))
o.append("")
for region, members in REGIONS:
    o.append("### %s\n" % region)
    for p in members:
        harbor, identity, _ = PORTS[p]
        head = "**%s**" % p if harbor == p else "**%s** (%s)" % (p, harbor)
        o.append(para("%s — %s" % (head, identity)))
        o.append("")

o.append("## Trade roles\n")
o.append(para("""
Roles are relative weights, not quantities. A major exporter is expected to be
among the roster's main sources of that good and to sustain repeatable routes; a
minor one supplies opportunistically or seasonally. The same reading applies to
demand. Buying and selling are independent: a combined code such as
`++exp/+imp` specifies major selling supply and minor buying demand. Export-only
roles represent local or hinterland producers; the re-export merchants listed
below instead buy and resell existing stock. Their buying weight is procurement
for resale, not end consumption. A dash means the port neither produces nor consumes the good in
meaningful volume, so no simulated actor there trades it. Player-to-player
trading remains permitted. Luxury auctions receive simulated participation only
where the role includes buying demand (including merchant buying). Export-only
and not-traded roles allow player-only luxury auctions, with a clear
"No simulated buyers" notice before consignment and on the listing. Buying
demand indicates eligibility, not guaranteed bids: budgets and capacity still
apply."""))
o.append("")
o.append("| Code | Meaning |")
o.append("|------|---------|")
for code, mean in ((E2,"major exporter"), (E1,"minor exporter"),
                   (I1,"minor importer"), (I2,"major importer"),
                   (X,"not traded")):
    o.append("| `%s` | %s |" % (code, mean))
o.append("")
base = 0
for cat, gs in CATEGORIES:
    o.append("### %s\n" % cat)
    o.append("| Port | " + " | ".join(gs) + " |")
    o.append("|------|" + "|".join("-" * (len(g) + 2) for g in gs) + "|")
    for p in ORDER:
        cells = [M[p][base + j] for j in range(len(gs))]
        o.append("| %s | %s |" % (p, " | ".join("`%s`" % c for c in cells)))
    o.append("")
    base += len(gs)

o.append("## Re-export merchants\n")
o.append(para("""
These entries identify merchant supply separately from local production. Merchants
buy existing goods at their port, occupy paid compatible warehouse space, and
resell only inventory they own and can commit. They generate no replacement stock;
empty inventory means no sell offer. Goods enter through player deliveries or
other valid local purchases, never through implicit off-map replenishment.
Buying and selling weights are separate targets, not guaranteed throughput.
Luxury merchants buy and sell through scheduled auctions; purchased stock can
only be consigned to a later auction whose bidding has not opened. They cannot
bid on their own lots or count a purchase as consumption. See DESIGN.md section 5
for budgets, reservations, and inventory-conservation rules."""))
o.append("")
o.append("| Port | Good | Buying | Selling |")
o.append("|------|------|--------|---------|")
for p in ORDER:
    for g, buying in REEXPORTS.get(p, {}).items():
        selling = M[p][GOODS.index(g)].split("/")[0]
        o.append(f"| {p} | {g} | `{buying}` | `{selling}` |")
o.append("")

o.append("## Physical and cost character\n")
o.append(para("""
Tiers are relative to the rest of the roster, not absolute figures. Storage
columns give leasable capacity by type, so a low reefer tier means refrigerated
blocks are genuinely scarce and expensive there. Handling covers berth
throughput; cost covers labour, port and handling fees. Max size is the largest
ship class a port admits, per the berth-group rules in section 4."""))
o.append("")
o.append("| Port | Berths | Ordinary | Reefer | Liquid | Handling | Cost | Max size |")
o.append("|------|--------|----------|--------|--------|----------|------|----------|")
for p in ORDER:
    b, ordn, ref, liq, hs, hc, sz = PORTS[p][2]
    o.append("| %s | %s | %s | %s | %s | %s | %s | %s |"
             % (p, b, ordn, ref, liq, hs, hc, SIZE[sz]))
o.append("")
o.append(para("""
Shanghai and Ho Chi Minh City are marked split: each has two berth groups gated
by ship size, so the largest classes berth only at Yangshan and Cai Mep
respectively. Houston admits everything below the largest class, reflecting the
Houston Ship Channel's draft. The largest class also cannot transit the Panama
Canal, which is a routing constraint rather than a port one."""))
o.append("")

# ---- generated coverage check -------------------------------------------
o.append("## Coverage check\n")
o.append(para("""
Section 5 requires every good to have several supplying and buying ports and
forbids exclusive access. These counts were derived from the tables above, and must
be re-derived whenever a role changes. Bulk commodities are held to at least four
suppliers and five buyers; every other good to at least three and four. A merchant
counts as both a supplier and a buyer, but never as a producer. Every good must
also retain at least one actual producer so merchant resale cannot masquerade
as production coverage."""))
o.append("")
o.append("| Good | Exporters | Importers |")
o.append("|------|-----------|-----------|")
bulk = set(CATEGORIES[0][1])
exp = lambda r: any(c in (E2, E1) for c in r.split("/"))
imp = lambda r: any(c in (I1, I2) for c in r.split("/"))
liquids = ["Crude oil", "Refined fuel", "Vegetable oil"]
petroleum = {"Crude oil", "Refined fuel"}
def can_ship(origin, destination, good):
    i = GOODS.index(good)
    return origin != destination and exp(M[origin][i]) and imp(M[destination][i])

def has_liquid_cycle():
    # Rotate every candidate cycle to start with its vegetable-oil leg.
    for a in ORDER:
        for b in ORDER:
            if not can_ship(a, b, "Vegetable oil"):
                continue
            if any(can_ship(b, a, g) for g in petroleum):
                return True
            for c in ORDER:
                if c in (a, b):
                    continue
                if any((g in petroleum or h in petroleum)
                       and can_ship(b, c, g) and can_ship(c, a, h)
                       for g in liquids for h in liquids):
                    return True
    return False

assert has_liquid_cycle(), "no two- or three-port liquid cycle includes vegetable oil and petroleum"
worst = []
for i, g in enumerate(GOODS):
    col = [M[p][i] for p in M]
    e = sum(1 for r in col if exp(r)); m = sum(1 for r in col if imp(r))
    te, ti = (4, 5) if g in bulk else (3, 4)
    assert e >= te and m >= ti, (g, e, m)
    assert any(r in (E1, E2) for r in col), (g, "no producer")
    worst.append((g, e, m))
    o.append("| %s | %d | %d |" % (g, e, m))
o.append("")
o.append(para("""
Bulk commodities take a lower floor for sellers than for buyers, four against
five. Real bulk export is source-concentrated: iron ore is dominated by a handful
of countries and crude oil by a few more, and this roster carries five sellers of
each because none of the remaining ports could plausibly be given ore or oil.
Raising the seller floor would force inventing a source at a transshipment hub or
an import gateway, which is a worse outcome than a narrow supply base. Buyers are
plentiful for both, so their floor stays higher.

Luxury demand is deliberately the narrowest on the roster. Section 6 gives
luxury goods shallow demand and competition for scarce lots, so only wealthy
consumer markets buy them. Whisky and jewelry have genuine producers here —
Japanese and American distilling, Indian and Belgian gem cutting — supplemented
by the collector-auction and re-export hubs at Hong Kong, Singapore and Dubai.
Designer clothing is the one luxury good with no coastal producer on the roster,
so Italian and French fashion reaches the sea through the inland catchments
behind Antwerp and Hamburg."""))
o.append("")
o.append("These properties must keep holding as the roster is balanced:\n")
for inv in [
 "Every good has at least three exporters and four importers; bulk commodities have at least four exporters and five importers.",
 "No good is exclusive to one port.",
 "Every good has an actual producer; re-export merchants buy and resell stock without producing it.",
 "Every port both imports and exports something, so round trips are possible everywhere.",
 "Crude oil and refined fuel have distinct enough sources that tankers have cargo in both directions.",
 "At least one two- or three-port cycle carries vegetable oil and crude oil or refined fuel. Each leg must have a seller at its origin and a buyer of the same good at its destination; ports in the cycle are distinct.",
 "Ports inside one cluster differ in at least half of their trade roles, since correlated prices leave specialization as their only distinction.",
 "Refrigerated capacity stays scarce enough that reefer-only perishables remain a constrained trade.",
]:
    o.append(textwrap.fill("- " + inv, width=W, subsequent_indent="  ",
                           break_long_words=False, break_on_hyphens=False))
o.append("")

io.open(ROOT / "docs/ports.md", "w", encoding="utf-8").write("\n".join(o).replace("Scrap aluminium", "Aluminium scrap"))
print("wrote docs/ports.md")
