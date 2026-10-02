defmodule TijaraTides.Domain.WeatherTest do
  use ExUnit.Case, async: true
  alias TijaraTides.Domain.{Weather, Ship, Fleet, VoyageNavigation}
  alias Ship.CargoBatch

  defp model,
    do: %{
      "period_ms" => 20_000,
      "duration_ms" => 1000,
      "chance_bps" => 10_000,
      "first_slot" => 1,
      "seed" => 1,
      "stagger" => false
    }

  defp route,
    do: %{"coordinates" => [[100, 10], [101, 10]], "passages" => [], "nautical_miles" => 10}

  defp ship,
    do: %Ship{
      id: "s",
      company_id: "c",
      name: "S",
      class: "freighter",
      port: "Jakarta",
      status: "docked",
      cargo: [],
      book_value: 1000,
      build_value: 1000,
      built_ms: 0,
      crew_remainder: 0,
      last_cost_ms: 15_000
    }

  defp voyage do
    w = Weather.forecast(route(), 10_000, 15_000, 15_000, model())

    Ship.begin_voyage(
      ship(),
      "Singapore",
      %{"duration_ms" => 10_000, "fuel" => 1000, "route" => route(), "weather" => w},
      15_000,
      600
    )
  end

  test "staggered storms span the full period deterministically without changing occurrence" do
    current = Weather.model(%{})
    span = current["period_ms"] - current["duration_ms"]

    offsets =
      for sector <- 0..23,
          slot <- 1..100,
          window = Weather.window("sector:#{sector}", slot, current),
          window != nil do
        assert window == Weather.window("sector:#{sector}", slot, current)
        assert window["until_ms"] - window["starts_ms"] == current["duration_ms"]
        offset = window["starts_ms"] - slot * current["period_ms"]
        assert offset >= 0 and offset < span
        offset
      end

    assert length(offsets) > 100

    for quarter <- 0..3 do
      count = Enum.count(offsets, &(div(&1 * 4, span) == quarter))
      assert count > div(length(offsets), 8)
    end

    for sector <- 0..23, slot <- 1..100 do
      region = "sector:#{sector}"
      chance = rem(:erlang.phash2({current["seed"], region, slot}, 1_000_000_000), 10_000)

      assert is_nil(Weather.window(region, slot, current)) ==
               chance >= current["chance_bps"]
    end

    forced = %{current | "chance_bps" => 10_000, "stagger" => false}
    assert Weather.window("sector:0", 1, forced)["starts_ms"] == forced["period_ms"]
    assert Weather.window("sector:0", 0, forced) == nil
    assert Weather.window("sector:0", 1, %{forced | "chance_bps" => 0}) == nil
  end

  test "staggered forecast reconciliation preserves settled movement across ticks and replay" do
    staggered = %{model() | "stagger" => true}
    forecast = Weather.forecast(route(), 100_000, 15_000, 15_000, staggered)

    sailing =
      Ship.begin_voyage(
        ship(),
        "Singapore",
        %{
          "duration_ms" => 100_000,
          "fuel" => 1000,
          "route" => route(),
          "weather" => forecast
        },
        15_000,
        600
      )

    c = %{"weather" => staggered}
    revised = Ship.apply_weather(sailing, route(), 100_000, 85_000, 600, c)
    assert revised.weather["delay_ms"] > 0
    {settled, _} = Ship.advance(revised, 100_000, 85_000, false, 600, 1000)
    assert Ship.apply_weather(settled, route(), 100_000, 0, 600, c) == settled

    intermediate = Ship.apply_weather(sailing, route(), 50_000, 35_000, 600, c)
    {intermediate, _} = Ship.advance(intermediate, 50_000, 35_000, false, 600, 1000)
    stepped = Ship.apply_weather(intermediate, route(), 100_000, 50_000, 600, c)
    {stepped, _} = Ship.advance(stepped, 100_000, 50_000, false, 600, 1000)
    assert stepped == settled
  end

  test "forecast shows only known storms and path regions handle the dateline" do
    assert Weather.forecast(route(), 10_000, 15_000, 15_000, model())["delay_ms"] == 0
    known = Weather.forecast(route(), 10_000, 20_500, 20_500, model())
    assert known["delay_ms"] == 500
    assert hd(known["holds"])["until_ms"] == 21_000
    assert map_size(Weather.active(20_500, model())) == 24
    assert Weather.active(21_000, model()) == %{}
    segments = Weather.segments(%{"coordinates" => [[179, 10], [-179, 10]]})
    assert length(segments) == 2

    assert Enum.map(segments, &elem(&1, 0)) == [
             Weather.region([179, 10]),
             Weather.region([-179, 10])
           ]

    assert elem(hd(segments), 1) == 0.0 and elem(List.last(segments), 2) == 1.0
  end

  test "mid-voyage storms revise arrival without backward motion, burning fuel or preserving spoiled cargo" do
    c = TijaraTides.Infrastructure.GameCatalogue.all()
    {before, _} = Ship.advance(voyage(), 19_000, 4000, false, 600, 1000)
    assert before.fuel_burned == 400

    before = %{
      before
      | cargo: [
          %CargoBatch{
            good: "fruit",
            quantity: 1,
            lot_id: "fruit",
            expires_ms: 20_250,
            unit_cost: 10
          }
        ]
    }

    paused = Ship.apply_weather(before, route(), 20_500, 1500, 600, c)
    assert paused.arrive_ms == 26_000
    {paused, effects} = Ship.advance(paused, 20_500, 1500, false, 600, 1000)
    assert paused.fuel_burned == 500 and effects.fuel == 100
    assert effects.spoilage == 10 and paused.cargo == []
    row = Ship.Rows.encode(paused)
    assert Fleet.progress(row, 20_500) == 0.5
    assert Fleet.progress(row, 20_800) == 0.5
    assert VoyageNavigation.split(row, 20_500, c) == VoyageNavigation.split(row, 20_800, c)
    assert Ship.apply_weather(paused, route(), 20_500, 0, 600, c) == paused
    restored = Ship.Rows.decode(Ship.Rows.encode(paused))
    {still, effects} = Ship.advance(restored, 20_800, 300, false, 600, 1000)
    assert effects.fuel == 0 and still.fuel_burned == 500
    assert still.crew_remainder > paused.crew_remainder
    {arrived, effects} = Ship.advance(still, 26_000, 5200, false, 600, 1000)
    assert arrived.status == "docked" and arrived.port == "Singapore"
    assert effects.fuel == 500 and arrived.fuel_burned == 1000
    assert arrived.weather == nil
  end

  test "forecast replay is independent of tick size and accepted tuning changes" do
    c = TijaraTides.Infrastructure.GameCatalogue.all()
    once = Ship.apply_weather(voyage(), route(), 24_000, 9000, 600, c)

    twice =
      voyage()
      |> Ship.apply_weather(route(), 20_500, 5500, 600, c)
      |> Ship.apply_weather(route(), 24_000, 3500, 600, %{"weather" => %{"chance_bps" => 0}})

    assert once == twice
    assert Weather.motion(once.depart_ms, once.arrive_ms, once.weather, 24_000) == 8000
    after_storm = Ship.apply_weather(voyage(), route(), 21_000, 6000, 600, c)
    assert after_storm.weather["delay_ms"] == 1000
    assert Fleet.progress(Ship.Rows.encode(after_storm), 21_000) == 0.5
  end

  test "legacy voyages acquire weather prospectively without replaying historical storms" do
    legacy = %{voyage() | weather: nil, voyage_path: nil, last_cost_ms: 20_500, fuel_burned: 550}
    c = %{"weather" => model()}
    next = Ship.apply_weather(legacy, route(), 20_500, 0, 600, c)
    assert next.weather["since_ms"] == 20_500
    assert next.weather["delay_ms"] == 500
    assert Fleet.progress(Ship.Rows.encode(next), 20_500) == 0.55
    assert next.fuel_burned == 550
    assert next.voyage_path == route()["coordinates"]
    changed = %{route() | "coordinates" => [[-10, -10], [-9, -10]]}
    assert Ship.apply_weather(next, changed, 20_500, 0, 600, c) == next
  end

  test "storms affect only regions crossed and timing preserves the exact cost settlement" do
    mixed = %{model() | "chance_bps" => 5000}
    active = Weather.active(20_500, mixed)
    storm_id = Map.keys(active) |> hd()
    quiet_id = Enum.find(0..23, &(not Map.has_key?(active, "sector:" <> Integer.to_string(&1))))

    sector_route = fn id ->
      longitude = rem(id, 6) * 60 - 150
      latitude = div(id, 6) * 45 - 67.5
      %{"coordinates" => [[longitude, latitude], [longitude + 1, latitude]], "passages" => []}
    end

    storm_index = storm_id |> String.replace("sector:", "") |> String.to_integer()

    assert Weather.forecast(sector_route.(storm_index), 10_000, 20_500, 20_500, mixed)["delay_ms"] ==
             500

    assert Weather.forecast(sector_route.(quiet_id), 10_000, 20_500, 20_500, mixed)["delay_ms"] ==
             0

    c = TijaraTides.Infrastructure.GameCatalogue.all()
    bulk = Ship.apply_weather(voyage(), route(), 24_000, 9000, 600, c)
    {bulk, total} = Ship.advance(bulk, 24_000, 9000, false, 600, 1000)
    step = Ship.apply_weather(voyage(), route(), 20_500, 5500, 600, c)
    {step, first} = Ship.advance(step, 20_500, 5500, false, 600, 1000)
    step = Ship.apply_weather(step, route(), 24_000, 3500, 600, c)
    {step, second} = Ship.advance(step, 24_000, 3500, false, 600, 1000)
    assert step == bulk
    assert Map.new(total, fn {key, _} -> {key, first[key] + second[key]} end) == total

    assert_raise ArgumentError, fn ->
      Weather.window("sector:0", 1, %{model() | "duration_ms" => 19_999})
    end
  end
end
