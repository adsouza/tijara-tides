# Coffee as a twenty-third cargo, and a catalogue that can grow

Adds coffee to the trade catalogue, and first makes the world able to receive a
good added after it was seeded. Written 2026-09-21.

## Why coffee

Every dry good sits on one side or the other of both hull ratios. A bulk
carrier holds 1,000,000 kg in 1,200,000 L, so it fills by volume above 1.2
L/kg; a balanced freighter holds 500,000 kg in 900,000 L and fills by volume
above 1.8. Sorted by value density, the dry catalogue looks like this:

| Good | cents/L | L/kg | Bulk / freighter | Bulk-carrier hold |
|------|---------|------|------------------|-------------------|
| Recovered plastics | 3 | 10.00 | vol / vol | $36,000 |
| Grain | 14 | 1.40 | **vol / wt** | $171,400 |
| Lumber | 16 | 3.20 | vol / vol | $187,500 |
| Iron ore | 20 | 0.60 | wt / wt | $120,000 |
| Aluminium scrap | 40 | 2.50 | vol / vol | $480,000 |
| Everyday clothing | 43 | 9.33 | vol / vol | $514,200 |
| Agricultural machinery | 44 | 3.60 | vol / vol | $528,000 |
| Appliances | 44 | 7.20 | vol / vol | $532,800 |
| Construction equipment | 60 | 2.50 | vol / vol | $720,000 |
| Turbines | 167 | 2.40 | vol / vol | $2,000,000 |
| Electronics | 200 | 10.00 | vol / vol | $2,400,000 |
| **Coffee** | **235** | **1.70** | **vol / wt** | **$2,820,000** |
| Copper scrap | 700 | 0.50 | wt / wt | $3,500,000 |
| Designer clothing | 2,000 | 5.00 | vol / vol | $24,000,000 |
| Whisky | 3,000 | 2.50 | vol / vol | $36,000,000 |
| Spices | 3,750 | 4.00 | vol / vol | $45,000,000 |
| Jewelry | 250,000 | 2.00 | vol / vol | $3,000,000,000 |

Grain is the only good in the band where the bulk carrier fills by volume and
the freighter by weight, and grain is the second-cheapest cargo in the game.
Every valuable dry good today is either bulky on both hulls or dense on both,
so the hull a valuable cargo wants is never in question. Coffee is grain's
stowage at seventeen times the value, which puts a real choice there.

Coffee's hold value is not itself novel; it falls between electronics and
copper scrap. What no good combines is tropical agricultural origin, bulk
stowage and high value. Grain is agricultural, bulk and cheap. Spices are
agricultural, tiny in volume and very expensive. Fruit is agricultural,
refrigerated and perishable. The middle of the agricultural range is empty, and
coffee is the crop that occupies it.

This reopens decision group 20, which records the 22-good catalogue as final.
The group stays complete; its count and its finality sentence change.

## The good

| Field | Value |
|-------|-------|
| `id` | `coffee` |
| `name` | Coffee |
| `category` | Mass consumer products |
| `reference_cents` | 400,000 |
| `weight_kg` | 1,000 |
| `volume_l` | 1,700 |
| `hold` | dry |
| `shelf_ms` | 0 |
| `manual` | true, derived from the category |

Reference value follows the catalogue's existing anchor, where a lot's price in
cents is about a hundred times the real dollar price of a tonne: grain's 20,000
against roughly $200 a tonne for wheat, and 400,000 against roughly $4,000 a
tonne for green coffee. Volume follows the same convention as grain's, a
stowage factor of about 1.7 cubic metres to the tonne expressed as litres.

Coffee is not perishable, for the reason section 6 already gives for spices:
real green coffee fades over a year or two, and modelling that would collapse
it into the perishables archetype and remove the distinction that earns it a
place.

The category is load-bearing rather than cosmetic. `gen-game-data.py` derives
`manual` as `category not in ['Luxury items','Industrial machinery']`, so
choosing Mass consumer products is what gives coffee a continuous order book
instead of auctions. Section 6 already states that this category spans a wide
value density, which coffee at 235 cents a litre extends without contradicting.
No new hold type, market mechanism or category is introduced.

## Trade roles

Four producers, twenty buyers, one port abstaining. Coffee becomes as scarce as
spices and lumber, the narrowest supply on the roster outside luxury goods.

| Role | Ports |
|------|-------|
| `++exp` | São Paulo, Ho Chi Minh City, Colón |
| `+exp` | Jakarta |
| `++imp` | Tokyo, Dubai, Rotterdam, Antwerp, Hamburg, New York City, Los Angeles |
| `+imp` | Shanghai, Busan, Hong Kong, Shenzhen, Guangzhou, Singapore, Manila, Colombo, Abu Dhabi, Valencia, Athens, Tangier, Houston |
| `—` | Mumbai |

Santos is the world's coffee port and takes the strongest export weight with
Vietnam and Central America beside it; Indonesia follows a step behind. Colón
gains the high-value anchor export it lacks, holding only bananas and weak
scrap today. Mumbai abstains because India grows its own. No re-export
merchants: a European reseller would blunt the reason to sail to the tropics,
which is the entire purpose of a scarce origin.

These counts were checked by generating the roster with the column in place.
Coffee reports 4 producers, 4 exporters and 20 importers, clearing the floor of
three and four, clearing the rule that importers match or exceed producers, and
leaving every cluster above the half-difference threshold that rises from 11 to
12 differing roles when the catalogue reaches 23 goods. The tightest pair, Hong
Kong and Shenzhen, differs in 13.

## Making the catalogue extensible

`PortCargoMarketWorld.initialize/2` creates markets only when the world holds
none. A world seeded before a good is added therefore never gains markets for
it, and nothing reports the gap: `validate_catalogue!` runs before the guard
and checks the catalogue against itself, never against the persisted world. The
good would appear in the catalogue, ports would carry roles for it, and no port
would trade it.

The same function's other branch already reconciles: when markets exist it
walks them and promotes any that became a manufacturing feedstock since the
last boot. Reconciling against the catalogue on boot is therefore established
intent, and the `map_size == 0` fork is what leaves it incomplete.

Replace the fork with a single walk over the catalogue's roles. For each port
and good, create the market when none exists, and apply the feedstock promotion
when one does. A world that is already complete writes nothing, because
`State.put/4` returns the state unchanged when the stored value matches, so no
entry reaches the change set. No code path anywhere deletes a market, so the
walk cannot resurrect something removed on purpose.

The two feedstock paths must stay distinct. Creating a feedstock market seeds
it, raising stock to at least 50 and demand by 450 within the 500 cap.
Promoting an existing market must not inject stock, and only lifts demand to at
least 50 within what its current stock leaves. Collapsing them into one
expression would hand free inventory to every existing feedstock market on the
next boot.

`PortCargoMarket.raw_goods/0` is a hardcoded list of goods produced without
imported inputs, and is the one place the catalogue is not the source of truth.
Coffee is an agricultural good with no recipe, so it belongs there. Deriving
the list from the catalogue is out of scope; the list gains one entry.

## Work

Generators, both of which must then be re-run:

- `scripts/gen-ports-roster.py`: add Coffee to the Mass consumer products
  entry in `CATEGORIES`, and insert its role in every row of `M` at the
  matching column position. Extend the "Adding a good" docstring to name the
  two count references it currently omits.
- `scripts/gen-game-data.py`: add Coffee to `tuning` and to `CARGO_IDS`.

Code:

- `lib/tijara_tides/domain/port_cargo_market_world.ex`: the unified walk.
- `lib/tijara_tides/domain/port_cargo_market.ex`: `"coffee"` in `raw_goods/0`.
- `lib/tijara_tides/localization/names.ex`: a `translate("Coffee")` clause,
  then `mix gettext.extract` only. Never merge: the extractor cannot see
  runtime lookups and merging prunes the translations it misses.

Prose carrying the catalogue count. The roster generator's docstring lists
three of these; it misses two, and correcting the docstring is part of the
work so the next good does not repeat the search.

- Section 6, the launch-catalogue table: coffee joins the Mass consumer
  products row.
- Section 6, the count sentence: 22 goods becomes 23, and the breakdown's
  "four mass consumer products" becomes five.
- Section 6: a paragraph justifying coffee's place, in the style the other
  goods have.
- Section 5: the sentence saying recipes use the 22 tradable goods.
- Decision group 20: the sentence recording the 22-good catalogue as final.
  The group stays complete.
- Section 4, which the docstring omits: "trade roles across all 22 goods".
- `gen-ports-roster.py` itself, which the docstring also omits: the generated
  preamble says "section 6 fixes the 22-good catalogue used here", so the
  count lives in the generator source rather than in `docs/ports.md`.

Section 16 needs no change; it counts decision groups, not goods.

Generated artifacts: `docs/ports.md` and `priv/game/catalogue.json`.

## Tests

- `test/docs/ports_roster_test.exs`: raise the expected `parsed.goods` count
  from 22 to 23. Every other invariant already passes against the 23-good
  roster and needs no change.
- Reconcile, in the market-world tests: a world missing one good's markets
  gains exactly those markets; a complete world produces an empty change set;
  an existing feedstock market gains demand but no stock; a newly created
  feedstock market gains both.
- Coffee reaches the order book rather than an auction, which follows from
  `manual` but should be asserted rather than assumed.

## Out of scope

No manufacturing recipe. Roasting would need a second good, and section 5
already abstracts non-catalogue inputs into local production costs.

No catalogue `version` bump or version-stamped reconcile. The field exists and
the generator never sets it; a stamp claiming the world is current while a
market is missing would restore the failure this removes.

No change to `bulk`, the scrap backhaul exemption, or any role outside the
coffee column.

No derivation of `raw_goods/0` from the catalogue, though this change is the
second piece of evidence that it should eventually be derived.

## Verification

- `python3 scripts/gen-ports-roster.py` and the catalogue generator, then
  `scripts/check-generated.py`.
- `mix test`, `mix format --check-formatted`,
  `mix compile --force --warnings-as-errors`.
- The coverage table reports Coffee as 4 producers, 4 exporters, 20 importers.
- A world seeded before the change, booted after it, holds 25 coffee markets
  and reports no other change.
