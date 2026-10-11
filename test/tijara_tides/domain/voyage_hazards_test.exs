defmodule TijaraTides.Domain.VoyageHazardsTest do
  use ExUnit.Case, async: true

  alias TijaraTides.Domain.{
    Piracy,
    Ship,
    ShipWorld,
    Weather,
    Fleet,
    Journal,
    Visibility,
    CompanyFinanceWorld
  }

  alias TijaraTides.Domain.Services.VoyageHazards

  defp route,
    do: %{"coordinates" => [[100, 10], [110, 10]], "passages" => [], "nautical_miles" => 100}

  defp fixture(kind \\ "militia") do
    {state, catalogue} = TijaraTides.CommandFuzzer.fixture()
    base = catalogue["piracy"]

    zone =
      base["zones"]["red_sea"]
      |> Map.merge(%{
        "name" => "Red Sea and Bab-el-Mandeb",
        "kind" => kind,
        "chance_bps" => 10_000,
        "campaign_bps" => 0,
        "polygon" => [[102, 9], [104, 9], [104, 11], [102, 11]]
      })

    zones = %{
      "first" => zone,
      "second" => %{zone | "polygon" => [[106, 9], [108, 9], [108, 11], [106, 11]]}
    }

    piracy = base |> Map.put("zones", zones) |> put_in(["kinds", kind, "hold_ms"], 2000)
    catalogue = catalogue |> Map.put("piracy", piracy) |> Map.put("weather", %{"chance_bps" => 0})
    {id, row} = Enum.find(state.entities["ships"], fn {_, s} -> s["class"] == "freighter" end)

    quote = %{
      "duration_ms" => 10_000,
      "fuel" => 1000,
      "route" => route(),
      "weather" => Weather.forecast(route(), 10_000, 0, 0, Weather.model(catalogue))
    }

    ship =
      row
      |> Ship.Rows.decode()
      |> Ship.begin_voyage("Singapore", quote, 0, 600)
      |> Ship.snapshot_piracy(piracy)

    state = TijaraTides.Domain.State.put(state, "ships", id, Ship.Rows.encode(ship))

    state =
      CompanyFinanceWorld.post(state, row["company_id"], "departure", [
        {"cash_reserved", 1000},
        {"cash_available", -1000}
      ])
      |> Journal.clear()

    {state, catalogue, id}
  end

  defp advance(state, catalogue, elapsed) do
    %{state | clock_ms: state.clock_ms + elapsed}
    |> VoyageHazards.advance(elapsed, catalogue, 600)
  end

  test "polygon partition finds a zone entered and left within a single leg and joins adjacent legs" do
    {_, catalogue, _} = fixture()
    assert [{"first", a, b}, {"second", c, d}] = Piracy.crossings(route(), catalogue["piracy"])
    assert_in_delta a, 0.2, 1.0e-10
    assert_in_delta b, 0.4, 1.0e-10
    assert_in_delta c, 0.6, 1.0e-10
    assert_in_delta d, 0.8, 1.0e-10
    split = %{route() | "coordinates" => [[100, 10], [103, 10], [110, 10]]}
    assert length(Piracy.crossings(split, catalogue["piracy"])) == 2
    assert Piracy.crossings(route(), nil) == []
  end

  test "real routes include narrow zones and wrap the dateline" do
    cat = TijaraTides.Infrastructure.GameCatalogue.all()
    assert length(Piracy.crossings(cat["routes"]["Antwerp|Busan"], cat["piracy"])) == 7
    assert Piracy.crossings(cat["routes"]["Hong Kong|Guangzhou"], cat["piracy"]) == []

    assert Enum.any?(
             Piracy.crossings(cat["routes"]["Busan|Houston"], cat["piracy"]),
             &(elem(&1, 0) == "caribbean")
           )
  end

  test "salt validation, fraction and roll determinism; durable snapshots contain no salt" do
    {state, catalogue, id} = fixture()
    ship = state.entities["ships"][id]
    snapshot = Piracy.snapshot(route(), catalogue["piracy"], id, 0)
    assert snapshot == ship["piracy"]
    refute Map.has_key?(snapshot["model"], "salt")

    assert_raise ArgumentError, fn ->
      Piracy.validate_salt!(Map.put(catalogue["piracy"], "salt", "short"))
    end

    for c <- snapshot["pending"] do
      assert c["from_fraction"] < c["attack_fraction"] and
               c["attack_fraction"] < c["into_fraction"]

      assert c["roll"] == :erlang.phash2({catalogue["piracy"]["salt"], id, 0, c["index"]}, 10_000)
    end

    assert_raise ArgumentError, fn ->
      Piracy.validate_salt!(Map.delete(catalogue["piracy"], "salt"))
    end
  end

  test "integer factors precede the cap; militia ignores hull speed and campaigns use the attack time" do
    {_, cat, _} = fixture("piracy")

    m =
      cat["piracy"]
      |> put_in(["zones", "first", "chance_bps"], 400)
      |> put_in(["zones", "first", "campaign_bps"], 10_000)
      |> put_in(["zones", "first", "guard_pct"], 90)

    c = Piracy.campaign("first", 2, m)

    assert Piracy.attack_bps("first", c["starts_ms"], m, 18, true) ==
             div(div(1600 * (100 - m["zones"]["first"]["guard_pct"]), 100) * 22, 18)

    assert Piracy.attack_bps("first", c["until_ms"], m, 22) == 400
    saturated = put_in(m, ["zones", "first", "chance_bps"], 9000)
    # corrected below by a separate cap witness
    assert Piracy.attack_bps("first", c["starts_ms"], saturated, 22, true) == 3600
    {_, militia, _} = fixture()
    assert Piracy.attack_bps("first", 0, militia["piracy"], 18) == 10_000
    assert Piracy.attack_bps("first", 0, militia["piracy"], 24) == 10_000
  end

  test "two attacks reforecast in order; replay and stepwise resolution preserve incidents and fuel" do
    {state, cat, id} = fixture()
    once = advance(state, cat, 11_000)
    assert length(once.entities["ships"][id]["piracy"]["incidents"]) == 2
    [a, b] = once.entities["ships"][id]["piracy"]["incidents"]
    second = List.last(state.entities["ships"][id]["piracy"]["pending"])
    assert b["starts_ms"] == round(second["attack_fraction"] * 10_000) + 2000
    assert once.entities["ships"][id]["arrive_ms"] == 14_000
    assert a["starts_ms"] >= state.entities["ships"][id]["last_cost_ms"]

    stepped =
      Enum.reduce(1..11, state, fn _, s -> advance(s, cat, 1000) |> Fleet.advance(1000) end)

    bulk = Fleet.advance(once, 11_000)
    assert stepped.entities["ships"][id] == bulk.entities["ships"][id]
    assert advance(once, cat, 0) == once
    altered = put_in(cat, ["piracy", "kinds", "militia", "hold_ms"], 999_999)
    assert advance(state, altered, 11_000).entities["ships"][id] == once.entities["ships"][id]
    arrived = advance(bulk, cat, 3000) |> Fleet.advance(3000)
    assert arrived.entities["ships"][id]["status"] == "docked"
    assert arrived.entities["ships"][id]["piracy"] == nil
    assert arrived.entities["ships"][id]["fuel_burned"] == 1000
  end

  test "a storm inside an incident adds no pause, and skip shortcuts preserve incidents" do
    incident = %{
      "id" => "incident",
      "source" => "piracy",
      "fraction" => 0.2,
      "starts_ms" => 2000,
      "until_ms" => 5000
    }

    model = %{
      "period_ms" => 10_000,
      "duration_ms" => 1000,
      "chance_bps" => 10_000,
      "first_slot" => 0,
      "seed" => 1,
      "stagger" => false
    }

    # Departure moves the attack hold over the storm at 10 seconds.
    incident = %{incident | "starts_ms" => 9000, "until_ms" => 12_000}
    w = Weather.forecast(route(), 10_000, 7000, 12_000, model, nil, nil, %{incidents: [incident]})
    assert w["delay_ms"] == 3000
    assert length(w["holds"]) == 1

    skipped =
      Weather.forecast(route(), 10_000, 7000, 7000, %{model | "first_slot" => 10}, nil, nil, %{
        incidents: [incident]
      })

    assert skipped["delay_ms"] == 3000
  end

  test "small boats are suppressed across the entry-to-attack interval, but militia is not" do
    {state, cat, id} = fixture("piracy")

    storm = %{
      "period_ms" => 10_000,
      "duration_ms" => 1000,
      "chance_bps" => 10_000,
      "first_slot" => 1,
      "seed" => 1,
      "stagger" => false
    }

    row = state.entities["ships"][id]

    pending =
      Enum.map(row["piracy"]["pending"], fn c ->
        Map.put(c, "attack_fraction", if(c["index"] == 0, do: 0.35, else: 0.75))
      end)

    row =
      row
      |> Map.put("depart_ms", 7000)
      |> Map.put("arrive_ms", 17_000)
      |> put_in(["piracy", "pending"], pending)
      |> Map.put("weather", Weather.forecast(route(), 10_000, 7000, 7000, storm))

    state = TijaraTides.Domain.State.put(%{state | clock_ms: 7000}, "ships", id, row)
    next = advance(state, cat, 6000)
    assert hd(next.entities["ships"][id]["piracy"]["resolved"])["outcome"] == "suppressed"
    crossing = hd(pending)
    weather = next.entities["ships"][id]["weather"]
    militia = put_in(cat["piracy"], ["zones", "first", "kind"], "militia")
    refute Piracy.suppressed?(crossing, 7000, weather, militia)
  end

  test "charges with no free cash become bills, leave fuel reserved, and insurance owes only the deductible" do
    {state, cat, id} = fixture()
    company_id = state.entities["ships"][id]["company_id"]
    company = state.entities["companies"][company_id]

    state =
      TijaraTides.Domain.State.put(state, "companies", company_id, %{
        company
        | "cash" => company["reserved"]
      })

    next = advance(state, cat, 5000)
    incident = hd(next.entities["ships"][id]["piracy"]["incidents"])
    assert next.entities["companies"][company_id]["reserved"] == company["reserved"]
    assert next.entities["companies"][company_id]["cash"] == company["reserved"]
    assert next.entities["companies"][company_id]["unpaid"] == incident["charge"]

    assert Enum.sum(for {_, bill} <- next.entities["operating_bills"], do: bill["remaining"]) ==
             incident["charge"]

    insured =
      put_in(state, [:entities, "ships", id, "piracy", "protection"], "insurance")
      |> advance(cat, 5000)

    recovered = hd(insured.entities["ships"][id]["piracy"]["incidents"])
    assert recovered["recovery"] == div(recovered["charge"] * 80, 100)

    assert insured.entities["companies"][company_id]["unpaid"] ==
             recovered["charge"] - recovered["recovery"]

    assert insured.entities["companies"][company_id]["profit"] ==
             company["profit"] - recovered["charge"] + recovered["recovery"]

    reports = TijaraTides.UseCases.CommitPreparation.prepare(Journal.clear(state), insured)

    assert reports.entities["financial_reports"][company_id <> ":quarter:0"]["operating"] ==
             recovered["charge"] - recovered["recovery"]
  end

  test "receivership resolves without charging; legacy voyages are exempt until diversion" do
    {state, cat, id} = fixture()
    company_id = state.entities["ships"][id]["company_id"]

    estate =
      put_in(state, [:entities, "companies", company_id, "bankruptcy_ms"], 0)
      |> advance(cat, 11_000)

    assert Enum.all?(
             estate.entities["ships"][id]["piracy"]["resolved"],
             &(&1["outcome"] == "exempt")
           )

    assert estate.entities["ships"][id]["piracy"]["incidents"] == []
    assert Map.get(estate, :journal, []) == []

    legacy =
      update_in(state, [:entities, "ships", id], &Map.delete(&1, "piracy"))
      |> advance(cat, 11_000)

    assert legacy.entities["ships"][id]["piracy"] == nil

    quote = %{
      "duration_ms" => 10_000,
      "fuel" => 1000,
      "route" => route(),
      "weather" => Weather.forecast(route(), 10_000, 11_000, 11_000, Weather.model(cat))
    }

    diverted = ShipWorld.reroute(legacy, id, "Tokyo", quote, 0, cat)
    assert length(diverted.entities["ships"][id]["piracy"]["pending"]) == 2
  end

  test "diversion retains records, continues a resolved zone without reroll, and blocks while held" do
    {state, cat, id} = fixture()
    next = advance(state, cat, 5000)
    ship = next.entities["ships"][id]

    account =
      next.entities["accounts"][next.entities["companies"][ship["company_id"]]["account_id"]]

    held_at = hd(ship["piracy"]["incidents"])["starts_ms"] + 1
    held = %{next | clock_ms: held_at}
    assert Fleet.reroute(held, account, id, "Tokyo", 1_000_000, cat) == {:error, :held_by_pirates}
    continued_route = %{route() | "coordinates" => [[103, 10], [110, 10]]}

    quote = %{
      "duration_ms" => 10_000,
      "fuel" => 1000,
      "route" => continued_route,
      "weather" => Weather.forecast(continued_route, 10_000, 5000, 5000, Weather.model(cat))
    }

    diverted = ShipWorld.reroute(next, id, "Tokyo", quote, 0, cat).entities["ships"][id]["piracy"]
    assert hd(diverted["resolved"]) == hd(ship["piracy"]["resolved"])
    assert Enum.find(diverted["resolved"], &(&1["index"] == 2))["outcome"] == "continued"
    assert Enum.map(diverted["pending"], & &1["index"]) == [3]
    assert diverted["incidents"] == ship["piracy"]["incidents"]
  end

  test "public holds omit charges, owner snapshots omit the salt and rolls, notices are idempotent" do
    {state, cat, id} = fixture()
    next = advance(state, cat, 5000)
    ship = next.entities["ships"][id]

    account =
      next.entities["accounts"][next.entities["companies"][ship["company_id"]]["account_id"]]

    public = Visibility.public(next, cat)["ships"][id]
    refute Map.has_key?(public, "piracy")

    for h <- public["weather"]["holds"] do
      refute Map.has_key?(h, "charge")
      refute Map.has_key?(h, "recovery")
    end

    private = Visibility.private(next, account)["ships"][id]["piracy"]
    refute Map.has_key?(private, "model")
    for c <- private["pending"], do: assert(Map.keys(c) |> Enum.sort() == ["index", "zone"])

    assert Enum.any?(next.entities["notices"], fn {key, n} ->
             String.starts_with?(key, "piracy:" <> id <> ":") and n["code"] == "ship.piracy"
           end)

    refute Map.has_key?(next.entities["notices"], "weather:" <> id)
    assert advance(next, cat, 0).entities["notices"] == next.entities["notices"]
  end

  test "settled oracle detects missing charge, recovery, duplicate indices and a held diversion" do
    {state, cat, id} = fixture()
    next = advance(state, cat, 5000)
    assert TijaraTides.SettledCheck.assert_settled!(state, next, cat, "tick") == next

    assert_raise ArgumentError, fn ->
      TijaraTides.SettledCheck.assert_settled!(state, Map.put(next, :journal, []), cat, "tick")
    end

    insured = put_in(state, [:entities, "ships", id, "piracy", "protection"], "insurance")
    changed = advance(insured, cat, 5000)

    broken =
      Map.update!(changed, :journal, fn events ->
        Enum.map(events, fn event ->
          Map.update!(
            event,
            :entries,
            &Enum.reject(&1, fn {code, n} -> code == "piracy_charge_expense" and n < 0 end)
          )
        end)
      end)

    assert_raise ArgumentError, fn ->
      TijaraTides.SettledCheck.assert_settled!(insured, broken, cat, "tick")
    end

    duplicate = update_in(next, [:entities, "ships", id, "piracy", "resolved"], &(&1 ++ [hd(&1)]))

    assert_raise ArgumentError, fn ->
      TijaraTides.SettledCheck.assert_settled!(state, duplicate, cat, "tick")
    end

    at = hd(next.entities["ships"][id]["piracy"]["incidents"])["starts_ms"] + 1
    held = %{next | clock_ms: at}

    assert_raise ArgumentError, fn ->
      TijaraTides.SettledCheck.assert_settled!(
        held,
        put_in(held, [:entities, "ships", id, "destination"], "Tokyo"),
        cat,
        "command"
      )
    end
  end

  test "sub-millisecond crossing positions still sequence holds in path order" do
    incident = %{
      "id" => "first",
      "source" => "piracy",
      "fraction" => 0.1,
      "starts_ms" => 0,
      "until_ms" => 2000
    }

    model = Weather.model(%{"weather" => %{"chance_bps" => 0}})
    weather = Weather.forecast(route(), 1, 0, 0, model, nil, nil, %{incidents: [incident]})
    assert Weather.time_at(weather, 0, 0.1) == 0
    assert Weather.time_at(weather, 0, 0.2) == 2000
  end

  test "a zero-charge incident still holds, and a zero-chance crossing safely misses" do
    {state, cat, id} = fixture()

    free =
      put_in(
        state,
        [:entities, "ships", id, "piracy", "model", "kinds", "militia", "charge_bps"],
        0
      )

    next = advance(free, cat, 5000)
    assert hd(next.entities["ships"][id]["piracy"]["incidents"])["charge"] == 0
    assert next.entities["ships"][id]["arrive_ms"] == 12_000
    assert Map.get(next, :journal, []) == []
    assert TijaraTides.SettledCheck.assert_settled!(free, next, cat, "tick") == next

    quiet =
      put_in(
        state,
        [:entities, "ships", id, "piracy", "model", "zones", "first", "chance_bps"],
        0
      )

    missed = advance(quiet, cat, 5000)
    assert hd(missed.entities["ships"][id]["piracy"]["resolved"])["outcome"] == "missed"
    assert missed.entities["ships"][id]["arrive_ms"] == 10_000
  end

  test "campaign announcements notify once per sailing ship with a pending crossing" do
    {state, cat, id} = fixture()
    model = put_in(cat["piracy"], ["zones", "first", "campaign_bps"], 10_000)
    campaign = Piracy.campaign("first", 1, model)
    announced = campaign["announced_ms"]
    ship = state.entities["ships"][id]

    ship =
      ship
      |> Map.put("depart_ms", announced)
      |> Map.put("arrive_ms", announced + 10_000)
      |> Map.put("last_cost_ms", announced)
      |> Map.put(
        "weather",
        Weather.forecast(route(), 10_000, announced, announced, Weather.model(cat))
      )
      |> Ship.Rows.decode()
      |> Ship.snapshot_piracy(model)
      |> Ship.Rows.encode()

    state = TijaraTides.Domain.State.put(%{state | clock_ms: announced}, "ships", id, ship)
    cat = Map.put(cat, "piracy", model)
    next = advance(state, cat, 0)
    key = "campaign:" <> campaign["window_id"] <> ":" <> id
    assert next.entities["notices"][key]["code"] == "ship.piracy_campaign"
    assert advance(next, cat, 0).entities["notices"] == next.entities["notices"]
  end
end
