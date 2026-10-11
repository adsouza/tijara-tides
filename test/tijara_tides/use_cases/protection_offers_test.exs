defmodule TijaraTides.UseCases.ProtectionOffersTest do
  use ExUnit.Case, async: true
  alias TijaraTides.Domain.{Fleet, Game, Piracy, State, Weather, Journal}
  alias TijaraTides.UseCases.GameQueries

  setup do
    cat =
      TijaraTides.Infrastructure.GameCatalogue.all() |> Map.put("weather", %{"chance_bps" => 0})

    s = Game.initialize(%{entities: %{}, clock_ms: 0, epoch: 1, revision: 0}, cat)
    {:ok, s, _} = Game.seed_invite(s, "invite")
    {:ok, s, _} = Game.redeem(s, "invite", "session", %{id: "a", wall_ms: 0})
    account = Game.get(s, "accounts", "a")

    {:ok, s, _} =
      TijaraTides.CompanyFixture.create_company(s, account, "a", "Tangier", "general", %{
        id: "co",
        catalogue: cat
      })

    %{s: Journal.clear(s), cat: cat, account: Game.get(s, "accounts", "a"), id: "co:1"}
  end

  defp offer(c, state), do: GameQueries.preview(state, c.cat, {:ok, c.account}, c.id, "Athens")

  defp funds(s, amount) do
    company = State.get(s, "companies", "co")
    State.put(s, "companies", "co", %{company | "cash" => amount, "reserved" => 0})
  end

  test "all offered departure choices accept exact cash, refuse one cent short, and post once",
       c do
    offered = offer(c, c.s)
    refute inspect(offered) =~ "attack_fraction"
    refute inspect(offered) =~ "salt"
    refute inspect(offered) =~ "roll"

    for choice <- ~w(none guards insurance both) do
      terms = offered["protection_options"][choice]
      required = offered["fuel"] + offered["canal_fees"] + terms["cost"]
      exact = funds(c.s, required)

      assert {:ok, next, _} =
               Fleet.sail(
                 exact,
                 c.account,
                 c.id,
                 "Athens",
                 offered["fuel"],
                 c.cat,
                 choice,
                 terms["cost"]
               )

      ship = State.get(next, "ships", c.id)
      assert ship["piracy"]["protection"] == choice

      assert State.get(next, "companies", "co")["cash"] -
               State.get(next, "companies", "co")["reserved"] == 0

      entries = Enum.flat_map(next.journal, & &1.entries)
      assert Enum.sum(for {"piracy_guard_expense", n} <- entries, do: n) == terms["guard_fee"]
      assert Enum.sum(for {"piracy_premium_expense", n} <- entries, do: n) == terms["premium"]

      assert {:error, {:departure_funds, _, _, _}} =
               Fleet.sail(
                 funds(c.s, required - 1),
                 c.account,
                 c.id,
                 "Athens",
                 offered["fuel"],
                 c.cat,
                 choice,
                 terms["cost"]
               )

      if terms["cost"] > 0 do
        assert {:error, :departure_protection_changed} =
                 Fleet.sail(
                   exact,
                   c.account,
                   c.id,
                   "Athens",
                   offered["fuel"],
                   c.cat,
                   choice,
                   terms["cost"] - 1
                 )
      end
    end
  end

  test "purchased guards reduce actual attacks and the oracle detects missing protection payment",
       c do
    cat =
      c.cat
      |> put_in(["piracy", "zones", "barbary_coast", "chance_bps"], 10_000)
      |> put_in(["piracy", "zones", "barbary_coast", "guard_pct"], 100)

    ship = State.get(c.s, "ships", c.id)
    q = Fleet.voyage_quote(ship, "Athens", cat, 0, nil, "guards")

    {:ok, s, _} =
      Fleet.sail(
        c.s,
        c.account,
        c.id,
        "Athens",
        q["fuel"],
        cat,
        "guards",
        q["protection_quote"]["cost"]
      )

    TijaraTides.SettledCheck.assert_settled!(c.s, s, cat, "sail")

    corrupt =
      Map.update!(s, :journal, fn events ->
        Enum.map(events, fn e ->
          %{e | entries: Enum.reject(e.entries, &(elem(&1, 0) == "piracy_guard_expense"))}
        end)
      end)

    assert_raise ArgumentError, ~r/protection_posting/, fn ->
      TijaraTides.SettledCheck.assert_settled!(c.s, corrupt, cat, "sail")
    end

    at = s.clock_ms + q["duration_ms"]

    next =
      TijaraTides.Domain.Services.VoyageHazards.advance(
        %{s | clock_ms: at},
        q["duration_ms"],
        cat,
        600
      )

    record = hd(State.get(next, "ships", c.id)["piracy"]["resolved"])
    assert record["outcome"] == "missed"
    assert record["charge"] == 0
  end

  test "insurance is absent on safe routes and forged protection choices and prices are refused",
       c do
    ship = State.get(c.s, "ships", c.id)
    q = Fleet.voyage_quote(ship, "Valencia", c.cat, 0)
    refute q["protection_options"]["insurance"]["insurance_available"]

    assert {:error, :departure_protection_changed} =
             Fleet.sail(c.s, c.account, c.id, "Valencia", q["fuel"], c.cat, "insurance", 2500)

    for choice <- [nil, %{}, "secret", 1],
        do:
          assert(
            {:error, :departure_protection_invalid} =
              Fleet.sail(c.s, c.account, c.id, "Athens", 1_000_000, c.cat, choice, 1_000_000)
          )

    for limit <- [nil, "2500", -1, %{}],
        do:
          assert(
            {:error, :departure_protection_changed} =
              Fleet.sail(c.s, c.account, c.id, "Athens", 1_000_000, c.cat, "both", limit)
          )
  end

  test "diversion keeps protection, prices only new crossings, and shares the offered affordability",
       c do
    offered = offer(c, c.s)
    cost = offered["protection_options"]["both"]["cost"]

    assert {:ok, s, _} =
             Fleet.sail(c.s, c.account, c.id, "Athens", offered["fuel"], c.cat, "both", cost)

    s = Journal.clear(s)
    ship = State.get(s, "ships", c.id)
    q = Fleet.reroute_quote(ship, "Busan", s.clock_ms, c.cat)
    assert q["protection_quote"]["protection"] == "both"
    assert q["protection_quote"]["cost"] > 0

    required =
      q["additional_fuel"] - q["released_fuel"] + q["canal_fees"] + q["protection_quote"]["cost"]

    company = State.get(s, "companies", "co")
    exact = State.put(s, "companies", "co", %{company | "cash" => company["reserved"] + required})

    assert {:ok, diverted, _} =
             Fleet.reroute(
               exact,
               c.account,
               c.id,
               "Busan",
               q["fuel"],
               c.cat,
               q["protection_quote"]["cost"]
             )

    assert State.get(diverted, "ships", c.id)["piracy"]["protection"] == "both"

    assert State.get(diverted, "companies", "co")["cash"] ==
             State.get(diverted, "companies", "co")["reserved"]

    short =
      State.put(exact, "companies", "co", %{
        State.get(exact, "companies", "co")
        | "cash" => company["reserved"] + required - 1
      })

    assert {:error, :reroute_funds} =
             Fleet.reroute(
               short,
               c.account,
               c.id,
               "Busan",
               q["fuel"],
               c.cat,
               q["protection_quote"]["cost"]
             )

    assert {:error, :reroute_invalid} =
             Fleet.reroute(
               exact,
               c.account,
               c.id,
               "Busan",
               q["fuel"],
               c.cat,
               q["protection_quote"]["cost"] - 1
             )
  end

  test "continued crossings have no guard fee or premium term", c do
    model = c.cat["piracy"]
    zone = model["zones"]["barbary_coast"]
    point = zone["label"]
    route = %{"coordinates" => [point, [5.0, 40.0]], "nautical_miles" => 100, "passages" => []}
    weather = Weather.forecast(route, 10_000, 0, 0, Weather.model(c.cat))

    previous = %{
      "resolved" => [%{"zone" => "barbary_coast", "index" => 0}],
      "next_index" => 1,
      "protection" => "both"
    }

    terms =
      Piracy.protection_quotes(route, State.get(c.s, "ships", c.id), 0, weather, model, previous)[
        "both"
      ]

    assert terms["crossings"] == []
    assert terms["cost"] == 0
  end

  test "all class and zone prices use configured fees and integer chance arithmetic", c do
    weather =
      Weather.forecast(c.cat["routes"]["Tangier|Athens"], 10_000, 0, 0, Weather.model(c.cat))

    for {class_id, class} <- Fleet.classes(), {zone_id, zone} <- c.cat["piracy"]["zones"] do
      crossing = %{
        "zone" => zone_id,
        "from_fraction" => 0.2,
        "into_fraction" => 0.8,
        "attack_fraction" => 0.5
      }

      ship = State.get(c.s, "ships", c.id) |> Map.put("class", class_id)
      offers = Piracy.crossing_quotes([crossing], ship, 0, weather, c.cat["piracy"])

      assert offers["guards"]["guard_fee"] ==
               div(class["price"] * zone["guard_fee_ppm"], 1_000_000)

      guarded = div(zone["chance_bps"] * (100 - zone["guard_pct"]), 100)

      expected =
        if c.cat["piracy"]["kinds"][zone["kind"]]["storm_suppressed"],
          do: div(guarded * 22, class["speed"]),
          else: guarded

      assert hd(offers["guards"]["crossings"])["chance_bps"] == expected
    end
  end

  test "quote suppresses known storms for small boats, while militia is still charged", c do
    storm = %{
      "period_ms" => 10_000,
      "duration_ms" => 1000,
      "chance_bps" => 10_000,
      "first_slot" => 1,
      "seed" => 1,
      "stagger" => false
    }

    route = %{"coordinates" => [[100, 10], [110, 10]], "nautical_miles" => 100, "passages" => []}
    weather = Weather.forecast(route, 10_000, 7000, 7000, storm)

    crossing = %{
      "zone" => "barbary_coast",
      "from_fraction" => 0.2,
      "into_fraction" => 0.4,
      "attack_fraction" => 0.35
    }

    ship = State.get(c.s, "ships", c.id)
    offers = Piracy.crossing_quotes([crossing], ship, 7000, weather, c.cat["piracy"])
    assert hd(offers["none"]["crossings"])["chance_bps"] == 0
    assert offers["insurance"]["premium"] == 2500
    militia = put_in(c.cat, ["piracy", "zones", "barbary_coast", "kind"], "militia")
    offers = Piracy.crossing_quotes([crossing], ship, 7000, weather, militia["piracy"])
    assert hd(offers["none"]["crossings"])["chance_bps"] == 150
  end

  test "protection tuning rejects malformed prices and retains legacy defaults", c do
    model = c.cat["piracy"]

    for {key, value} <- [
          {"recovery_pct", 101},
          {"recovery_pct", "80"},
          {"loading_pct", 99},
          {"loading_pct", 1001},
          {"guard_fee_bps", -1},
          {"minimum_premium", -1},
          {"minimum_premium", 1_000_000_001}
        ] do
      assert_raise ArgumentError, fn ->
        Piracy.validate!(put_in(model, ["protection", key], value))
      end
    end

    assert_raise ArgumentError, fn ->
      Piracy.validate!(put_in(model, ["zones", "barbary_coast", "guard_fee_ppm"], -1))
    end

    assert Piracy.protection_settings(Map.delete(model, "protection"))["recovery_pct"] == 80
  end

  test "quotes use guards before cap, skip suppressed odds, and ignore future unannounced campaigns",
       c do
    ship = State.get(c.s, "ships", c.id)
    route = c.cat["routes"]["Tangier|Athens"]

    model =
      c.cat["piracy"]
      |> put_in(["first_slot"], 0)
      |> put_in(["campaign"], %{
        "period_ms" => 100_000,
        "duration_ms" => 50_000,
        "warning_ms" => 0,
        "multiplier" => 4
      })
      |> put_in(["zones", "barbary_coast", "campaign_bps"], 10_000)

    window = Piracy.campaign("barbary_coast", 0, model)
    # Force the forecast attack into a campaign not yet announced at departure.
    crossing = hd(Piracy.snapshot(route, model, ship["id"], 0)["pending"])
    duration = round((window["starts_ms"] + 100) / crossing["attack_fraction"])
    weather = Weather.forecast(route, duration, 0, 0, Weather.model(c.cat))
    q = Piracy.protection_quotes(route, ship, 0, weather, model)

    assert hd(q["none"]["crossings"])["chance_bps"] ==
             model["zones"]["barbary_coast"]["chance_bps"]

    departure = window["starts_ms"]
    weather = Weather.forecast(route, 1000, departure, departure, Weather.model(c.cat))
    q = Piracy.protection_quotes(route, ship, departure, weather, model)
    assert hd(q["none"]["crossings"])["chance_bps"] == 600
    assert hd(q["guards"]["crossings"])["chance_bps"] == 240
    assert q["both"]["premium"] <= q["insurance"]["premium"]

    assert q["insurance"]["premium"] ==
             max(2500, div(div(600 * 160_000 * 80, 1_000_000) * 140, 100))
  end
end
