defmodule TijaraTides.Domain.PiracyCrossingsTest do
  use ExUnit.Case, async: false
  alias TijaraTides.Domain.{Fleet, Piracy}
  alias TijaraTides.Infrastructure.GameCatalogue

  defp ship(port),
    do: %{
      "id" => "crossings",
      "class" => "freighter",
      "port" => port,
      "cargo" => [],
      "built_ms" => 0
    }

  defp calculations(fun) do
    mfa = {Piracy, :calculate_crossings, 2}
    :erlang.trace_pattern(mfa, true, [:local, :call_count])

    try do
      fun.()
      {:call_count, count} = :erlang.trace_info(mfa, :call_count)
      count
    after
      :erlang.trace_pattern(mfa, false, [:local, :call_count])
    end
  end

  test "every prepared route preserves exact crossings, private snapshots and quotes" do
    catalogue = GameCatalogue.all()
    model = Piracy.model(catalogue)
    raw = Map.delete(model, :crossings)
    uncached = Map.put(catalogue, "piracy", raw)

    for {key, route} <- catalogue["routes"] do
      [port, destination] = String.split(key, "|")
      ship = ship(port)
      assert Piracy.crossings(route, model) == Piracy.crossings(route, raw), key

      assert Piracy.snapshot(route, model, ship["id"], 123_456) ==
               Piracy.snapshot(route, raw, ship["id"], 123_456),
             key

      assert Fleet.voyage_quote(ship, destination, catalogue, 123_456) ==
               Fleet.voyage_quote(ship, destination, uncached, 123_456),
             key
    end
  end

  test "repeated risky and empty-crossing quotes never recompute geometry" do
    catalogue = GameCatalogue.all()
    uncached = update_in(catalogue["piracy"], &Map.delete(&1, :crossings))

    assert calculations(fn -> Fleet.voyage_quote(ship("Antwerp"), "Busan", uncached, 0) end) == 1

    assert calculations(fn ->
             for _ <- 1..100,
                 {port, destination} <- [{"Antwerp", "Busan"}, {"Tangier", "Valencia"}] do
               Fleet.voyage_quote(ship(port), destination, catalogue, 0)
             end
           end) == 0
  end

  test "a changed path or polygon falls back to the actual geometry" do
    catalogue = GameCatalogue.all()
    model = Piracy.model(catalogue)
    route = catalogue["routes"]["Tangier|Athens"]
    changed_path = Map.put(route, "coordinates", [[-40, -20], [-39, -20]])
    polygon = [[-40, -20], [-39, -20], [-39, -19], [-40, -19]]
    changed_model = put_in(model["zones"]["barbary_coast"]["polygon"], polygon)

    for {path, rules} <- [{changed_path, model}, {route, changed_model}] do
      assert calculations(fn ->
               assert Piracy.crossings(path, rules) ==
                        Piracy.crossings(path, Map.delete(rules, :crossings))
             end) == 2

      refute Piracy.crossings(path, rules) == Piracy.crossings(route, model)
    end
  end

  test "tuning changes reuse geometry without freezing prices or private rolls" do
    catalogue = GameCatalogue.all() |> Map.put("weather", %{"chance_bps" => 0})
    model = put_in(catalogue["piracy"]["zones"]["barbary_coast"]["chance_bps"], 10_000)["piracy"]
    route = catalogue["routes"]["Tangier|Athens"]
    raw = Map.delete(model, :crossings)

    assert calculations(fn -> Piracy.crossings(route, model) end) == 0
    assert Piracy.snapshot(route, model, "a", 0) == Piracy.snapshot(route, raw, "a", 0)
    refute Piracy.snapshot(route, model, "a", 0) == Piracy.snapshot(route, model, "b", 1)

    tuned = Fleet.voyage_quote(ship("Tangier"), "Athens", Map.put(catalogue, "piracy", model), 0)
    baseline = Fleet.voyage_quote(ship("Tangier"), "Athens", catalogue, 0)

    assert tuned ==
             Fleet.voyage_quote(ship("Tangier"), "Athens", Map.put(catalogue, "piracy", raw), 0)

    assert tuned["protection_options"]["insurance"]["cost"] >
             baseline["protection_options"]["insurance"]["cost"]
  end

  test "derived crossings stay out of public definitions and persisted models" do
    catalogue = GameCatalogue.all()
    model = catalogue["piracy"]
    assert model[:crossings]
    route = catalogue["routes"]["Antwerp|Busan"]
    snapshot = Piracy.snapshot(route, model, "a", 0)
    refute Map.has_key?(snapshot["model"], :crossings)
    refute Map.has_key?(snapshot["model"], "salt")
    assert Jason.decode!(Jason.encode!(snapshot)) == snapshot
    assert GameCatalogue.public()["piracy"] == Piracy.public_model(model)
    Jason.encode!(GameCatalogue.public())
  end

  test "diversions reuse the index only when their frozen polygons still match" do
    catalogue = GameCatalogue.all()
    route = catalogue["routes"]["Tangier|Athens"]
    snapshot = Piracy.snapshot(route, catalogue["piracy"], "a", 0)
    ship = Map.put(ship("Tangier"), "piracy", snapshot)

    assert calculations(fn -> Piracy.crossings(route, Piracy.voyage_model(ship, catalogue)) end) ==
             0

    historical =
      put_in(ship["piracy"]["model"]["zones"]["barbary_coast"]["polygon"], [
        [-40, -20],
        [-39, -20],
        [-39, -19],
        [-40, -19]
      ])

    model = Piracy.voyage_model(historical, catalogue)
    assert model["zones"] == historical["piracy"]["model"]["zones"]
    assert calculations(fn -> assert Piracy.crossings(route, model) == [] end) == 1
  end
end
