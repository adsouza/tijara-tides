defmodule TijaraTides.Domain.FundingTransitionsTest do
  # Each transition that invalidates visit funding releases it itself; no command or
  # tick phase sweeps the world afterwards. `revalidate` must then find nothing to do.
  use ExUnit.Case, async: true

  alias TijaraTides.Domain.{Commands, CompanyFinanceWorld, Game, ShipWorld, Simulation, State}
  alias TijaraTides.Domain.Services.{DepartureFunding, RouteEditing}

  setup do
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

    m = State.get(s, "markets", "Jakarta|lumber")
    s = State.put(s, "markets", "Jakarta|lumber", %{m | "stock" => 0, "demand" => 0})
    %{s: s, a: State.get(s, "accounts", "a"), cat: cat}
  end

  defp command(c, s, command, id \\ "cmd") do
    {:ok, s, _} = Commands.execute(s, c.a, command, %{id: id, catalogue: c.cat})
    s
  end

  defp edit(c, s, id, params) do
    {:ok, s, _} =
      RouteEditing.execute(s, c.a, Map.put(params, "ship", "co:1"), %{id: id, catalogue: c.cat})

    s
  end

  defp route(c, s) do
    s
    |> then(&edit(c, &1, "co:1:a", %{"operation" => "add_stop", "port" => "Jakarta"}))
    |> then(&edit(c, &1, "co:1:b", %{"operation" => "add_stop", "port" => "Singapore"}))
  end

  defp budget(c, s, params) do
    {:ok, s, _} = DepartureFunding.configure_visit(s, c.a, Map.put(params, "ship", "co:1"), c.cat)
    s
  end

  defp free(s, n) do
    company = State.get(s, "companies", "co")
    delta = n - company["cash"] + company["reserved"]

    CompanyFinanceWorld.post(s, "co", "test_funds", [
      {"cash_available", delta},
      {"capital", -delta}
    ])
  end

  defp reserved(s), do: State.get(s, "companies", "co")["reserved"]

  defp settled!(s, c) do
    assert DepartureFunding.revalidate(s, ["co:1"], c.cat) == s
    s
  end

  defp sail(c, s, destination),
    do:
      command(c, s, %{
        "action" => "sail",
        "ship" => "co:1",
        "destination" => destination,
        "fuel_limit" => 86_400_000
      })

  test "rerouting away from a funded stop releases its inbound budget", c do
    s =
      route(c, c.s)
      |> then(&edit(c, &1, "start", %{"operation" => "start", "auto_depart" => true}))
      |> then(&budget(c, &1, %{"stop" => "co:1:b", "amount" => 1000}))
      |> then(&sail(c, &1, "Singapore"))

    assert State.get(s, "visit_budgets", "co:1:b")["remaining"] == 1000

    s =
      command(c, %{s | clock_ms: s.clock_ms + 1000}, %{
        "action" => "reroute",
        "ship" => "co:1",
        "destination" => "Colombo",
        "fuel_limit" => 86_400_000
      })

    assert State.get(s, "visit_budgets", "co:1:b") == nil
    settled!(s, c)
  end

  test "an automatic departure releases order budgets for ports it no longer visits", c do
    {:ok, s, _} = ShipWorld.change_onward(c.s, c.a, "co:1", "Jakarta", "Singapore", c.cat, true)

    {:ok, s, _} =
      ShipWorld.add_instruction(
        s,
        c.a,
        %{
          "ship" => "co:1",
          "port" => "Colombo",
          "good" => "lumber",
          "side" => "buy",
          "quantity" => 1,
          "limit" => 100,
          "budget" => 200,
          "onward" => "Jakarta"
        },
        %{id: "colombo", catalogue: c.cat}
      )

    s = budget(c, s, %{"port" => "Colombo", "amount" => 500})
    assert State.get(s, "visit_budgets", "co:1|Colombo")["remaining"] == 500

    t = Simulation.advance(s, 1000, c.cat)
    assert State.get(t, "ships", "co:1")["destination"] == "Singapore"
    assert State.get(t, "visit_plans", "co:1|Colombo") == nil
    assert State.get(t, "visit_budgets", "co:1|Colombo") == nil
    settled!(t, c)
  end

  describe "a waiting departure request" do
    setup c do
      cat =
        Map.put(c.cat, "departure_funding", %{
          "wait_ms" => 100,
          "window_ms" => 50,
          "cooldown_ms" => 200
        })

      s =
        route(c, c.s)
        |> then(&edit(c, &1, "start", %{"operation" => "start", "auto_depart" => true}))
        |> then(&budget(c, &1, %{"stop" => "co:1:b", "amount" => 1000}))
        |> ShipWorld.prepare_visits(cat)
        |> free(100)

      s =
        DepartureFunding.advance(s, cat)
        |> Map.put(:clock_ms, 100)
        |> DepartureFunding.advance(cat)

      assert State.get(s, "departure_requests", "co:1")["accumulated"] == 100
      %{s: s, cat: cat}
    end

    test "is abandoned by the policy change itself", c do
      s = command(c, c.s, %{"action" => "funding_policy", "policy" => "reduced"})
      assert State.entities(s, "departure_requests") == %{}
      assert reserved(s) == 0
      settled!(s, c)
    end

    test "is abandoned when the ship departs manually", c do
      s = free(c.s, 1_000_000) |> then(&sail(c, &1, "Singapore"))
      assert State.get(s, "ships", "co:1")["status"] == "sailing"
      assert State.get(s, "departure_requests", "co:1") == nil
      settled!(s, c)
    end
  end

  test "a route wait timing out releases that stop's budget in the same phase", c do
    s =
      route(c, c.s)
      |> then(
        &edit(c, &1, "rule", %{
          "operation" => "add_rule",
          "stop" => "co:1:a",
          "side" => "buy",
          "good" => "lumber",
          "quantity" => 5,
          "limit" => 100
        })
      )
      |> then(
        &edit(c, &1, "wait", %{
          "operation" => "set_wait",
          "stop" => "co:1:a",
          "max_wait_ms" => 1000
        })
      )
      |> then(&budget(c, &1, %{"stop" => "co:1:a", "amount" => 300}))
      |> then(&edit(c, &1, "start", %{"operation" => "start", "auto_depart" => true}))
      |> ShipWorld.prepare_visits(c.cat)

    assert State.get(s, "visit_budgets", "co:1:a")["remaining"] == 300

    s = DepartureFunding.expire_route_waits(%{s | clock_ms: 2000}, c.cat)
    assert State.get(s, "ship_routes", "co:1")["wait_timed_out"]
    assert State.get(s, "visit_budgets", "co:1:a") == nil
    settled!(s, c)
  end
end
