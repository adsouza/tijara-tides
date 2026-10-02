defmodule TijaraTides.Domain.AutomationCostTest do
  use ExUnit.Case, async: false
  alias TijaraTides.Domain.{Game, State, Fleet, Ship, Weather, AutomationWorld}
  alias TijaraTides.Domain.Services.DepartureFunding

  # Count calls in this process, instead of asserting a machine-dependent runtime.
  defp counted(mfa, pattern, run) do
    Code.ensure_loaded!(elem(mfa, 0))
    tracer = spawn(fn -> collect(0) end)
    assert :erlang.trace_pattern(mfa, pattern, [:local]) == 1
    :erlang.trace(self(), true, [:call, {:tracer, tracer}])

    try do
      result = run.()
      :erlang.trace(self(), false, [:call])
      delivered = :erlang.trace_delivered(self())

      receive do
        {:trace_delivered, _, ^delivered} -> :ok
      after
        1000 -> flunk("Trace delivery timed out")
      end

      send(tracer, {:count, self()})

      receive do
        {:count, count} -> {result, count}
      after
        1000 -> flunk("Trace collector timed out")
      end
    after
      :erlang.trace(self(), false, [:call])
      :erlang.trace_pattern(mfa, false, [:local])
      Process.exit(tracer, :kill)
    end
  end

  defp collect(n) do
    receive do
      {:trace, _, :call, _} -> collect(n + 1)
      {:count, caller} -> send(caller, {:count, n})
    end
  end

  test "funding reconciliation reads the instruction table once for one or many requests" do
    cat = TijaraTides.Infrastructure.GameCatalogue.all()
    s = Game.initialize(%{entities: %{}, clock_ms: 0, epoch: 1, revision: 0}, cat)
    {:ok, s, _} = Game.seed_invite(s, "invite")
    {:ok, s, _} = Game.redeem(s, "invite", "session", %{id: "a", wall_ms: 0})

    {:ok, s, _} =
      TijaraTides.CompanyFixture.create_company(
        s,
        State.get(s, "accounts", "a"),
        "Trader",
        "Jakarta",
        "general",
        %{id: "co", catalogue: cat}
      )

    template = State.get(s, "ships", "co:1")

    for size <- [1, 25, 100] do
      prepared =
        Enum.reduce(1..size, s, fn i, s ->
          id = "request-#{i}"
          ship = %{template | "id" => id}

          s =
            State.put(s, "ships", id, ship)
            |> State.put("visit_plans", id <> "|Jakarta", %{
              "id" => id <> "|Jakarta",
              "ship_id" => id,
              "company_id" => "co",
              "port" => "Jakarta",
              "onward" => "Singapore",
              "auto_depart" => true,
              "departure_wait" => nil,
              "advance_budget" => nil
            })

          quote = Fleet.voyage_quote(ship, "Singapore", cat, 0)

          AutomationWorld.request(
            s,
            DepartureFunding.spec(s, ship, "Singapore"),
            "wait",
            quote["fuel"] + quote["canal_fees"]
          )
        end)

      {reconciled, reads} =
        counted({State, :entities, 2}, [{[:_, "ship_instructions"], [], []}], fn ->
          DepartureFunding.reconcile(prepared, cat)
        end)

      assert reads == 1
      assert map_size(State.entities(reconciled, "departure_requests")) == size
      assert reconciled.entities == prepared.entities
    end
  end

  test "a legacy sailing path is partitioned once, then cached across ticks and serialization" do
    route = %{"coordinates" => [[100, 10], [160, -10]]}
    cat = %{"weather" => %{"chance_bps" => 0}}

    ship = %Ship{
      id: "s",
      company_id: "c",
      class: "freighter",
      status: "sailing",
      depart_ms: 0,
      arrive_ms: 100_000,
      last_cost_ms: 0,
      voyage_speedup: 600,
      weather: nil
    }

    {next, partitions} =
      counted({Weather, :segments, 1}, true, fn ->
        Enum.reduce(1..100, ship, fn tick, ship ->
          Ship.apply_weather(ship, route, tick * 10, 10, 600, cat)
        end)
      end)

    assert partitions == 1
    assert next.weather["segments"] == Enum.map(Weather.segments(route), &Tuple.to_list/1)
    restored = %{next | weather: next.weather |> Jason.encode!() |> Jason.decode!()}

    {same, partitions} =
      counted({Weather, :segments, 1}, true, fn ->
        Ship.apply_weather(restored, route, 1000, 0, 600, cat)
      end)

    assert partitions == 0
    assert same == restored
  end

  test "cached and newly partitioned forecasts agree across routes, seeds and cutoffs" do
    for path <- [[[100, 0], [190, -55]], [[-170, 60], [170, -60]], [[0, 0], [0, 0]]],
        seed <- 1..5,
        cutoff <- [0, 20_500, 40_000, 80_000] do
      route = %{"coordinates" => path}

      model =
        Weather.model(%{
          "weather" => %{
            "seed" => seed,
            "period_ms" => 20_000,
            "duration_ms" => 1000,
            "chance_bps" => 5000
          }
        })

      expected = Weather.forecast(route, 100_000, 0, cutoff, model)

      assert Weather.forecast(route, 100_000, 0, cutoff, model, nil, expected["segments"]) ==
               expected
    end
  end
end
