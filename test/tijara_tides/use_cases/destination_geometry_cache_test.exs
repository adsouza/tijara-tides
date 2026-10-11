defmodule TijaraTides.UseCases.DestinationGeometryCacheTest do
  use ExUnit.Case, async: false
  alias TijaraTides.Domain.{Fleet, Markets, Piracy, Visibility, Weather}
  alias TijaraTides.UseCases.{DestinationGeometryCache, DestinationMatrixCache, GameQueries}

  setup do
    {state, catalogue} = TijaraTides.CommandFuzzer.fixture()
    ports = ["Singapore", "Colombo", "Dubai"]

    catalogue =
      catalogue
      |> Map.put("ports", Map.take(catalogue["ports"], ports))
      |> Map.update!(
        "routes",
        &Map.filter(&1, fn {id, _} -> Enum.all?(String.split(id, "|"), fn p -> p in ports end) end)
      )
      |> Map.update!("piracy", &Piracy.public_model/1)

    view = %{
      public: Visibility.public(state, catalogue),
      private: Visibility.private(state, state.entities["accounts"]["account"]),
      markets: Markets.quotes(state, catalogue)
    }

    ship =
      Map.merge(view.private["ships"]["company:1"], %{
        "port" => "Singapore",
        "class" => "freighter"
      })

    view =
      view
      |> put_in([:private, "ships", ship["id"]], ship)
      |> put_in([:private, "company", "cash"], 100_000_000)

    functions = [{Piracy, :calculate_crossings, 2}, {Weather, :segments, 1}]
    for {module, _, _} <- functions, do: Code.ensure_loaded!(module)
    for mfa <- functions, do: :erlang.trace_pattern(mfa, true, [:local, :call_count])

    on_exit(fn ->
      for mfa <- functions, do: :erlang.trace_pattern(mfa, false, [:local, :call_count])
    end)

    %{definitions: %{catalogue: catalogue}, view: view, ship: ship, functions: functions}
  end

  defp counts(c),
    do: Enum.map(c.functions, fn mfa -> elem(:erlang.trace_info(mfa, :call_count), 1) end)

  test "ticks, cargo and finances recalculate estimates without rebuilding static geometry", c do
    {first, geometry} = DestinationMatrixCache.calculate(c.definitions, c.view, c.ship, nil)
    n = map_size(c.definitions.catalogue["routes"])
    assert counts(c) == [n, n]

    for clock <- [1, 1_800_000, 3_600_000], class <- ["freighter", "tanker"] do
      ship =
        Map.merge(c.ship, %{
          "class" => class,
          "cargo" => [
            %{"good" => "fruit", "quantity" => 1, "unit_cost" => 100, "expires_ms" => 2}
          ]
        })

      view =
        c.view
        |> put_in([:public, "clock_ms"], clock)
        |> put_in([:private, "company", "cash"], 1_000_000)
        |> put_in([:private, "ships", ship["id"]], ship)

      before = counts(c)
      {result, reused} = DestinationMatrixCache.calculate(c.definitions, view, ship, geometry)
      assert counts(c) == before
      assert reused === geometry
      refute result.key === first.key
      assert result.matrix === GameQueries.destination_matrix(c.definitions, view, ship)
    end
  end

  test "tuning reuses partitions but keeps weather, campaigns and protection quotes live", c do
    {geometry, _} = DestinationGeometryCache.prepare(nil, c.definitions)

    tuned =
      c.definitions
      |> put_in([:catalogue, "weather", "chance_bps"], 10_000)
      |> put_in([:catalogue, "weather", "stagger"], false)
      |> put_in([:catalogue, "piracy", "campaign", "multiplier"], 7)

    before = counts(c)
    {reused, prepared} = DestinationGeometryCache.prepare(geometry, tuned)
    assert reused === geometry
    assert counts(c) == before
    assert prepared.catalogue["weather"]["chance_bps"] == 10_000
    assert prepared.catalogue["piracy"]["campaign"]["multiplier"] == 7

    for clock <- [0, 1_800_000, 3_600_000], choice <- ~w(none guards insurance both) do
      actual = Fleet.voyage_quote(c.ship, "Colombo", prepared.catalogue, clock, clock, choice)
      expected = Fleet.voyage_quote(c.ship, "Colombo", tuned.catalogue, clock, clock, choice)
      assert actual === expected
      refute Map.has_key?(actual["weather"]["model"], :segments)
    end
  end

  test "changed paths and polygons rebuild only the affected kind of geometry", c do
    {geometry, _} = DestinationGeometryCache.prepare(nil, c.definitions)
    zone = c.definitions.catalogue["piracy"]["zones"] |> Map.keys() |> hd()

    changed_polygons =
      put_in(c.definitions, [:catalogue, "piracy", "zones", zone, "polygon"], [
        [0, 0],
        [2, 0],
        [2, 2],
        [0, 2]
      ])

    before = counts(c)
    {polygon_cache, prepared} = DestinationGeometryCache.prepare(geometry, changed_polygons)
    [piracy, weather] = counts(c)
    assert piracy > hd(before)
    assert weather == List.last(before)
    assert polygon_cache.weather === geometry.weather

    assert GameQueries.destination_matrix(prepared, c.view, c.ship) ===
             GameQueries.destination_matrix(changed_polygons, c.view, c.ship)

    changed_path =
      put_in(c.definitions, [:catalogue, "routes", "Singapore|Colombo", "coordinates"], [
        [0, 0],
        [2, 2]
      ])

    before = counts(c)
    {path_cache, prepared} = DestinationGeometryCache.prepare(geometry, changed_path)

    assert Enum.zip(counts(c), before)
           |> Enum.all?(fn {after_count, before_count} -> after_count > before_count end)

    refute path_cache.paths === geometry.paths

    assert GameQueries.destination_matrix(prepared, c.view, c.ship) ===
             GameQueries.destination_matrix(changed_path, c.view, c.ship)
  end

  test "uncatalogued weather paths fall back to geometry and forecast results stay exact", c do
    {_, prepared} = DestinationGeometryCache.prepare(nil, c.definitions)

    route =
      Map.put(c.definitions.catalogue["routes"]["Singapore|Colombo"], "coordinates", [
        [-50, 10],
        [50, 10]
      ])

    model = Weather.model(prepared.catalogue)
    before = counts(c)
    actual = Weather.forecast(route, 5_000_000, 1_800_000, 1_800_000, model)
    assert List.last(counts(c)) == List.last(before) + 1

    assert actual ===
             Weather.forecast(
               route,
               5_000_000,
               1_800_000,
               1_800_000,
               Map.delete(model, :segments)
             )
  end
end
