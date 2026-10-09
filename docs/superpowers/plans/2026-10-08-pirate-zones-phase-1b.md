# Pirate Zones Phase 1b Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the Singapore Strait, English Channel and Barbary Coast zones,
lower the Malacca Strait, notch and raise the South China Sea, and enforce a
12-nautical-mile harbour buffer, before any attack exists.

**Architecture:** All zone data lives in `scripts/gen-game-data.py` and is
generated into `priv/game/catalogue.json`. The generator gains a great-circle
buffer check that samples polygon edges every 0.01° or less; the Elixir
catalogue test repeats it with the same sampling. No runtime code changes:
`PiracyWorld`, the query and the map already iterate the catalogue's zones.

**Tech Stack:** Python generator, Elixir/ExUnit, Gettext (English and Arabic).

**Spec:** `docs/superpowers/specs/2026-10-08-pirate-zones-design.md`, phase 1b
(Zones section, Testing "Catalogue (phase 1b)" bullet, Delivery).

## Global Constraints

- Zones, kinds, chances and guard effects exactly as the spec's Zones table:
  Singapore Strait boarding 600 bps / 60%; Malacca Strait 150 bps; English
  Channel piracy 100 bps / 60%; Barbary Coast piracy 150 bps / 60%; others
  unchanged. Campaign chance 2,500 bps for the three new zones.
- Campaign names: Horsburgh raiders, Bintan boarders (Singapore Strait);
  Dunkirkers, Sea Beggars (English Channel); Algiers corsairs, Barbarossa's
  fleet (Barbary Coast).
- No port inside a zone; no zone within 12.0 nautical miles of a harbour
  (great-circle distance to the nearest sampled edge point, edges sampled at
  most every 0.01° in the lon/lat plane); no two zones overlap.
- Generated artifacts are regenerated, never hand-edited. Gettext extract only;
  Arabic complete. Zero warnings. Commit on `main`.

## Review Focus

1. The buffer check at its boundary: the generator and the Elixir test must
   agree for an edge at 11.9 and 12.1 nautical miles. Pinned in Task 1.
2. Lanes, not just ports: Tangier–Valencia and Hong Kong–Guangzhou cross no
   zone; Tangier–Athens crosses the Barbary Coast; Singapore–Busan crosses the
   Singapore Strait but not the Malacca Strait; Antwerp–Busan crosses seven.
   Pinned in Task 2.
3. Persisted campaign rows from the five-zone world after deploy: new zones
   appear on the next refresh, existing windows unchanged (seed, zone id, slot
   and campaign chance unchanged for old zones). Pinned in Task 2 by asserting
   literal campaign windows captured from the phase 1 catalogue.
4. Zone counts hard-coded at 5 in map and query tests. Updated in Task 2.
5. Arabic names for the three zones and six campaigns. Pinned by the existing
   translatability test in Task 2.

---

### Task 1: Harbour buffer in the generator and the catalogue test

**Files:**
- Modify: `scripts/gen-game-data.py` (piracy checks after the overlap check)
- Modify: `test/tijara_tides/domain/piracy_catalogue_test.exs`

**Interfaces:**
- Produces: Python `piracy_harbour_nm(point, ring)`; Elixir test helper
  `harbour_nm(point, ring)` using `VoyageNavigation.distance/2`.

- [ ] **Step 1: Write the failing Elixir test**

Add to `piracy_catalogue_test.exs`:

```elixir
  # Great-circle distance from a harbour to the nearest sampled edge point;
  # edges are sampled at most every 0.01 degrees, as the generator does.
  defp harbour_nm(point, ring) do
    ring
    |> Enum.zip(tl(ring) ++ [hd(ring)])
    |> Enum.flat_map(fn {[x1, y1], [x2, y2]} ->
      steps = max(1, ceil(max(abs(x2 - x1), abs(y2 - y1)) / 0.01))
      for k <- 0..steps, do: [x1 + (x2 - x1) * k / steps, y1 + (y2 - y1) * k / steps]
    end)
    |> Enum.map(&TijaraTides.Domain.VoyageNavigation.distance(point, &1))
    |> Enum.min()
  end

  test "the buffer measure separates 11.9 from 12.1 nautical miles" do
    square = fn d -> [[d, -1.0], [d + 1, -1.0], [d + 1, 1.0], [d, 1.0]] end
    assert_in_delta harbour_nm([0.0, 0.0], square.(11.9 / 60.04)), 11.9, 0.05
    assert_in_delta harbour_nm([0.0, 0.0], square.(12.1 / 60.04)), 12.1, 0.05
  end

  test "every zone keeps 12 nautical miles clear of every harbour" do
    catalogue = GameCatalogue.all()

    for {id, zone} <- Piracy.model(catalogue)["zones"],
        {port, %{"coordinates" => point}} <- catalogue["ports"] do
      assert harbour_nm(point, zone["polygon"]) >= 12.0, "#{port} is within 12 nm of #{id}"
    end
  end
```

- [ ] **Step 2: Run, then break once**

Run: `mix test test/tijara_tides/domain/piracy_catalogue_test.exs`
Expected: PASS today (the nearest harbour is Singapore at 38.8 nm from
Malacca). The guard is new, so prove it: temporarily move the Malacca
polygon's vertex `[103.2,1.6]` to `[103.65,1.3]` in the generator,
regenerate, and run the test. Expected: FAIL naming Singapore. Restore and
regenerate.

- [ ] **Step 3: Add the generator check**

After the overlap assertions for piracy zones in `scripts/gen-game-data.py`:

```python
def piracy_harbour_nm(point, ring):
    best = None
    for (x1, y1), (x2, y2) in zip(ring, ring[1:] + ring[:1]):
        steps = max(1, math.ceil(max(abs(x2 - x1), abs(y2 - y1)) / 0.01))
        for k in range(steps + 1):
            d = distance(point, [x1 + (x2 - x1) * k / steps, y1 + (y2 - y1) * k / steps])
            best = d if best is None or d < best else best
    return best
_square = lambda d: [[d, -1.0], [d + 1, -1.0], [d + 1, 1.0], [d, 1.0]]
assert piracy_harbour_nm([0.0, 0.0], _square(11.9 / 60.04)) < 12.0
assert piracy_harbour_nm([0.0, 0.0], _square(12.1 / 60.04)) >= 12.0
for zid, zone in piracy['zones'].items():
    for port, data in ports.items():
        assert piracy_harbour_nm(data['coordinates'], zone['polygon']) >= 12.0, \
            f'{port} lies within 12 nautical miles of piracy zone {zid}'
```

Confirm `math` is imported and that `distance(a, b)` (line 74) returns
nautical miles; if `distance` takes another argument order or unit, adapt the
call, not the rule.

- [ ] **Step 4: Regenerate and verify**

Run: `python3 scripts/gen-game-data.py && python3 scripts/check-generated.py`
Expected: catalogue unchanged (`git diff --stat priv/game/catalogue.json`
empty); generated check passes.

Break once: temporarily change `_square(12.1 / 60.04)` to
`_square(11.95 / 60.04)` in the generator self-check: the generator must fail
its assertion. Restore.

- [ ] **Step 5: Commit**

```bash
git add scripts/gen-game-data.py test/tijara_tides/domain/piracy_catalogue_test.exs
git commit -m "Keep pirate zones 12 nautical miles clear of every harbour"
```

---

### Task 2: The three new zones, Malacca lowered, South China Sea reshaped

**Files:**
- Modify: `scripts/gen-game-data.py` (zones)
- Regenerate: `priv/game/catalogue.json`
- Modify: `lib/tijara_tides/localization/names.ex`, `priv/gettext/ar/LC_MESSAGES/default.po`
- Modify: `test/tijara_tides/domain/piracy_catalogue_test.exs` (ids, counts,
  lanes, unchanged windows)
- Modify: `test/tijara_tides/infrastructure/map_piracy_test.exs:35` and
  `test/tijara_tides/use_cases/piracy_zones_query_test.exs:29` (5 → 8)

- [ ] **Step 1: Write the failing tests**

In `piracy_catalogue_test.exs`, replace the id list with
`~w(barbary_coast caribbean english_channel gulf_of_aden malacca red_sea singapore_strait south_china_sea)`,
replace the counts map with:

```elixir
    assert crossed == %{
             "red_sea" => 202,
             "gulf_of_aden" => 206,
             "singapore_strait" => 194,
             "malacca" => 194,
             "south_china_sea" => 220,
             "caribbean" => 76,
             "english_channel" => 128,
             "barbary_coast" => 192
           }

    assert model["zones"]["malacca"]["chance_bps"] == 150
    assert model["zones"]["singapore_strait"]["chance_bps"] == 600
```

and add a lane test, using a `zones_on/2` helper built from the same leg
sampler as the counts (extract that sampler into a private function first so
both tests share it):

```elixir
  test "lanes, not just ports, fall where the zones intend" do
    catalogue = GameCatalogue.all()
    zones = Piracy.model(catalogue)["zones"]
    on = fn key -> zones_on(catalogue["routes"][key]["coordinates"], zones) end

    assert on.("Tangier|Valencia") == []
    assert on.("Hong Kong|Guangzhou") == []
    assert on.("Tangier|Athens") == ["barbary_coast"]
    assert "singapore_strait" in on.("Singapore|Busan")
    refute "malacca" in on.("Singapore|Busan")

    assert on.("Antwerp|Busan") ==
             ~w(barbary_coast english_channel gulf_of_aden malacca red_sea singapore_strait south_china_sea)
  end

  test "the original five zones keep their phase 1 campaign windows" do
    model = Piracy.model(GameCatalogue.all())

    for {id, slot, starts} <- @phase_1_windows,
        do: assert(Piracy.campaign(id, slot, model)["starts_ms"] == starts)
  end
```

`@phase_1_windows` is a literal list captured **before** changing any zone
data, from the phase 1 catalogue: for each of the five original zones, the
first three slots with a campaign and their `starts_ms`. Capture it with:

```bash
mix run --no-start -e 'm = TijaraTides.Infrastructure.GameCatalogue.all()["piracy"]
for id <- ~w(caribbean gulf_of_aden malacca red_sea south_china_sea),
    {slot, c} <- (for s <- 1..400, c = TijaraTides.Domain.Piracy.campaign(id, s, m), c, do: {s, c}) |> Enum.take(3),
    do: IO.puts("{\"#{id}\", #{slot}, #{c["starts_ms"]}},")'
```

The Malacca rows guard that lowering its base chance leaves its campaign
windows alone, because windows depend only on seed, zone id, slot and campaign
chance.

Change the zone counts in `map_piracy_test.exs:35` and
`piracy_zones_query_test.exs:29` from 5 to 8.

Run: `mix test test/tijara_tides/domain/piracy_catalogue_test.exs test/tijara_tides/use_cases/piracy_zones_query_test.exs`
Expected: FAIL on the id list, counts and lanes.

- [ ] **Step 2: Change the zone data**

In the generator's `piracy['zones']`: set `malacca` `chance_bps` to 150; set
`south_china_sea` `polygon` to
`[[109.0,6.0],[119.0,6.0],[119.0,21.5],[111.0,21.5],[111.0,20.0],[109.0,20.0]]`;
add:

```python
  'singapore_strait':{'name':'Singapore Strait','kind':'boarding','chance_bps':600,'campaign_bps':2500,'guard_pct':60,
   'campaign_names':['Horsburgh raiders','Bintan boarders'],'label':[104.35,1.3],
   'polygon':[[104.0,1.05],[104.7,1.05],[104.7,1.5],[104.0,1.5]]},
  'english_channel':{'name':'English Channel','kind':'piracy','chance_bps':100,'campaign_bps':2500,'guard_pct':60,
   'campaign_names':['Dunkirkers','Sea Beggars'],'label':[-2.5,49.85],
   'polygon':[[-5.8,48.8],[-2.0,49.3],[0.5,49.9],[1.4,50.6],[1.75,50.95],[1.3,51.2],[0.2,50.6],[-2.5,50.4],[-5.8,49.9]]},
  'barbary_coast':{'name':'Barbary Coast','kind':'piracy','chance_bps':150,'campaign_bps':2500,'guard_pct':60,
   'campaign_names':['Algiers corsairs',"Barbarossa's fleet"],'label':[5.0,37.6],
   'polygon':[[-1.0,36.45],[-1.0,37.0],[1.0,37.4],[4.0,37.8],[7.0,38.2],[10.0,38.5],[10.0,37.4],[9.0,37.35],[7.0,37.25],[5.0,37.0],[3.0,36.95],[1.0,36.6]]},
```

Regenerate: `python3 scripts/gen-game-data.py`. Each label must lie inside its
polygon (the generator asserts it).

- [ ] **Step 3: Names and Arabic**

Add `translate/1` clauses in `names.ex` for Singapore Strait, English Channel,
Barbary Coast, Horsburgh raiders, Bintan boarders, Dunkirkers, Sea Beggars,
Algiers corsairs and Barbarossa's fleet. Run `mix gettext.extract` and append:

| msgid | msgstr |
|---|---|
| Singapore Strait | مضيق سنغافورة |
| English Channel | القنال الإنجليزي |
| Barbary Coast | ساحل البربر |
| Horsburgh raiders | غزاة هورسبرغ |
| Bintan boarders | مقتحمو بينتان |
| Dunkirkers | قراصنة دنكيرك |
| Sea Beggars | شحاذو البحر |
| Algiers corsairs | قراصنة الجزائر |
| Barbarossa's fleet | أسطول بربروس |

Run: `python3 scripts/check-gettext-catalogues.py`.

- [ ] **Step 4: Run the tests**

Run: `mix test test/tijara_tides/domain/piracy_catalogue_test.exs test/tijara_tides/domain/piracy_test.exs test/tijara_tides/use_cases/piracy_zones_query_test.exs && python3 scripts/test-game-db.py -- test/tijara_tides/infrastructure/map_piracy_test.exs`
Expected: PASS, zero warnings.

Break once: temporarily lower the Barbary polygon's `[1.0,37.4]` vertex north
edge to reach Spain (`[1.0,38.0]`, `[-1.0,37.7]`); the lane test must fail on
Tangier–Valencia. Restore and regenerate.

- [ ] **Step 5: Commit**

```bash
git add scripts/gen-game-data.py priv/game/catalogue.json lib/tijara_tides/localization/names.ex priv/gettext test/tijara_tides
git commit -m "Add the Singapore Strait, English Channel and Barbary Coast zones"
```

---

### Task 3: Documentation and full gates

**Files:** `docs/IMPLEMENTATION.md` (Pirate zones section), `docs/ux-inventory.md`
(regenerate).

- [ ] **Step 1:** Rewrite the IMPLEMENTATION.md "Pirate zones and campaigns"
  section's first paragraph as a whole paragraph: eight zones with kinds, the
  basis split (modern: Red Sea, Gulf of Aden, Singapore and Malacca Straits;
  historical: South China Sea, Caribbean, English Channel, Barbary Coast), the
  12-nautical-mile harbour buffer, and the counts: 202 Red Sea, 206 Gulf of
  Aden, 194 Singapore Strait, 194 Malacca Strait, 220 South China Sea, 76
  Caribbean, 128 English Channel, 192 Barbary Coast.
- [ ] **Step 2:** `python3 scripts/gen-ux-inventory.py && scripts/check-local.sh --full`.
  Expected: all gates pass, zero warnings.
- [ ] **Step 3:** Commit `Document the phase 1b pirate zones`.
