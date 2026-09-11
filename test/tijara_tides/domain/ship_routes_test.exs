defmodule TijaraTides.Domain.ShipRoutesTest do
  use ExUnit.Case, async: true
  alias TijaraTides.Domain.{Game, ShipRoutes, ShipInstructions, State, Fleet}

  def setup_game do
    catalogue = TijaraTides.Infrastructure.GameCatalogue.all()
    state = Game.initialize(%{entities: %{}, clock_ms: 0, epoch: 1, revision: 0}, catalogue)
    {:ok, state, _} = Game.seed_invite(state, "invite")
    {:ok, state, _} = Game.redeem(state, "invite", "session", %{id: "account", wall_ms: 0})
    account = Game.get(state, "accounts", "account")
    ctx = %{id: "company", catalogue: catalogue}

    {:ok, state, _} =
      TijaraTides.CompanyFixture.execute(
        state,
        account,
        %{
          "action" => "company",
          "name" => "Ocean Company",
          "port" => "Jakarta",
          "package" => "general"
        },
        ctx,
        catalogue
      )

    {state, Game.get(state, "accounts", "account"), catalogue}
  end

  setup do
    {state, account, catalogue} = setup_game()
    %{state: state, account: account, catalogue: catalogue}
  end

  defp command(c, state, id, params) do
    ShipRoutes.execute(state, c.account, Map.merge(%{"ship" => "company:1"}, params), %{
      id: id,
      catalogue: c.catalogue
    })
  end

  defp route(c, auto \\ true) do
    {:ok, s, _} = command(c, c.state, "s1", %{"operation" => "add_stop", "port" => "Jakarta"})
    {:ok, s, _} = command(c, s, "s2", %{"operation" => "add_stop", "port" => "Singapore"})

    {:ok, s, _} =
      command(c, s, "buy1", %{
        "operation" => "add_rule",
        "stop" => "s1",
        "side" => "buy",
        "good" => "lumber",
        "quantity" => 3,
        "limit" => 1_000_000,
        "budget" => 10_000_000
      })

    {:ok, s, _} =
      command(c, s, "sell1", %{
        "operation" => "add_rule",
        "stop" => "s2",
        "side" => "sell",
        "good" => "lumber",
        "quantity" => 3,
        "limit" => 0
      })

    {:ok, s, _} = command(c, s, "start", %{"operation" => "start", "auto_depart" => auto})
    s
  end

  test "maximum buys current stock and sell-all resolves the actual arrival load", c do
    s = route(c)

    for_rule = fn state, id ->
      rule = Game.get(state, "route_rules", id)

      State.put(
        state,
        "route_rules",
        id,
        Map.merge(rule, %{"quantity_mode" => "maximum", "quantity" => nil})
      )
    end

    s = for_rule.(s, "buy1") |> for_rule.("sell1")
    market = Game.get(s, "markets", "Jakarta|lumber")
    s = State.put(s, "markets", "Jakarta|lumber", %{market | "stock" => 7})
    s = ShipInstructions.advance(s, c.catalogue)
    assert lots(s) == 7
    assert Game.get(s, "ship_instructions", "route:buy1")["status"] == "filled"
    s = until(s, c, &(plan(&1)["visit"] == 1 and ship(&1)["status"] == "unloading"), 100)
    assert Game.get(s, "ship_instructions", "route:sell1")["quantity"] == 7
    assert lots(s) == 0
  end

  for {constraint, stock} <- [{"supplier stock", 7}, {"hold capacity", 1_000}] do
    test "maximum purchase with excess cash stops at #{constraint} and can depart", c do
      s = route(c)
      company = Game.get(s, "companies", "company")
      s = State.put(s, "companies", "company", %{company | "cash" => 1_000_000_000})
      rule = Game.get(s, "route_rules", "buy1")

      s =
        State.put(
          s,
          "route_rules",
          "buy1",
          Map.merge(rule, %{
            "quantity_mode" => "maximum",
            "quantity" => nil,
            "budget" => 1_000_000_000
          })
        )

      market = Game.get(s, "markets", "Jakarta|lumber")
      s = State.put(s, "markets", "Jakarta|lumber", %{market | "stock" => unquote(stock)})
      item = c.catalogue["goods"]["lumber"]
      class = Fleet.classes()[ship(s)["class"]]

      maximum =
        min(
          unquote(stock),
          min(
            div(class["weight"], item["weight_kg"]),
            div(class["volume"], item["volume_l"])
          )
        )

      s = ShipInstructions.advance(s, c.catalogue)
      assert lots(s) == maximum
      order = Game.get(s, "ship_instructions", "route:buy1")
      assert order["status"] == "filled"
      assert order["filled"] == maximum
      assert order["quantity"] == maximum
      assert Game.get(s, "markets", "Jakarta|lumber")["stock"] == unquote(stock) - maximum
      assert Game.get(s, "companies", "company")["cash"] > 0
      s = until(s, c, &(ship(&1)["status"] == "sailing"), 100)
      assert lots(s) == maximum
    end
  end

  for {case_name, demand, budget, sold} <- [
        {"limited demand", 2, 100_000_000, 2},
        {"no demand", 0, 100_000_000, 0},
        {"exhausted buyer budget", 10, 0, 0}
      ] do
    test "sell-all continues with unsold cargo after #{case_name}", c do
      s = route(c) |> ShipInstructions.advance(c.catalogue)
      assert lots(s) == 3
      vessel = ship(s)

      s =
        State.put(s, "ships", vessel["id"], %{
          vessel
          | "port" => "Singapore",
            "status" => "docked"
        })

      route = plan(s)
      s = State.put(s, "ship_routes", route["id"], %{route | "cursor" => 1, "phase" => "arrival"})
      rule = Game.get(s, "route_rules", "sell1")

      s =
        State.put(
          s,
          "route_rules",
          "sell1",
          Map.merge(rule, %{"quantity_mode" => "maximum", "quantity" => nil})
        )

      market = Game.get(s, "markets", "Singapore|lumber")

      s =
        State.put(s, "markets", "Singapore|lumber", %{
          market
          | "demand" => unquote(demand),
            "budget" => unquote(budget)
        })

      s = ShipInstructions.advance(s, c.catalogue)
      order = Game.get(s, "ship_instructions", "route:sell1")
      assert order["status"] == "filled"
      assert order["filled"] == unquote(sold)
      assert lots(s) == 3 - unquote(sold)
      s = until(s, c, &(ship(&1)["status"] == "sailing"), 100)
      assert lots(s) == 3 - unquote(sold)
    end
  end

  test "running rule edits preserve materialized orders and removals preserve execution mode",
       c do
    s = route(c)
    rule = Game.get(s, "route_rules", "buy1")

    {:ok, s, _} =
      command(
        c,
        s,
        "edit",
        Map.merge(rule, %{
          "operation" => "update_rule",
          "rule" => "buy1",
          "stop" => "s1",
          "quantity_mode" => "maximum"
        })
      )

    s = ShipRoutes.advance(s, c.catalogue)
    order = Game.get(s, "ship_instructions", "route:buy1")
    assert order["quantity_mode"] == "maximum"

    {:ok, s, _} =
      command(
        c,
        s,
        "edit2",
        Map.merge(rule, %{
          "operation" => "update_rule",
          "rule" => "buy1",
          "stop" => "s1",
          "quantity" => 1
        })
      )

    assert Game.get(s, "ship_instructions", "route:buy1") == order
    {:ok, s, _} = command(c, s, "remove", %{"operation" => "remove_rule", "rule" => "buy1"})
    market = Game.get(s, "markets", "Jakarta|lumber")
    s = State.put(s, "markets", "Jakarta|lumber", %{market | "stock" => 2})
    s = ShipInstructions.advance(s, c.catalogue)
    assert lots(s) == 2
    assert Game.get(s, "ship_instructions", "route:buy1")["status"] == "filled"
  end

  test "future stop edits preserve the active cursor and protect committed stops", c do
    s = route(c)
    {:ok, s, _} = command(c, s, "s3", %{"operation" => "add_stop", "port" => "Colombo"})

    assert {:error, :route_stop_committed} =
             command(c, s, "remove", %{"operation" => "remove_stop", "stop" => "s1"})

    assert {:error, :route_stop_committed} =
             command(c, s, "remove", %{"operation" => "remove_stop", "stop" => "s2"})

    {:ok, s, _} = command(c, s, "remove", %{"operation" => "remove_stop", "stop" => "s3"})
    assert plan(s)["cursor"] == 0
    assert length(ShipRoutes.stops(s, "company:1")) == 2
  end

  test "resuming without an opt-in enables automatic travel around the circuit", c do
    s = route(c, false)
    {:ok, s, _} = command(c, s, "pause", %{"operation" => "pause"})
    {:ok, s, _} = command(c, s, "resume", %{"operation" => "resume"})
    assert plan(s)["auto_depart"]
    s = until(s, c, &(plan(&1)["visit"] >= 2), 100)
    assert plan(s)["status"] == "running"
  end

  for mode <- ["fixed", "maximum"] do
    test "#{mode} purchases work without a cap and retain voyage funds", c do
      s = route(c)
      rule = Game.get(s, "route_rules", "buy1")

      {:ok, s, _} =
        command(
          c,
          s,
          "uncapped",
          Map.merge(rule, %{
            "operation" => "update_rule",
            "rule" => "buy1",
            "stop" => "s1",
            "budget" => nil,
            "quantity_mode" => unquote(mode)
          })
        )

      market = Game.get(s, "markets", "Jakarta|lumber")
      s = State.put(s, "markets", "Jakarta|lumber", %{market | "stock" => 5})
      s = ShipInstructions.advance(s, c.catalogue)
      order = Game.get(s, "ship_instructions", "route:buy1")
      assert order["budget"] == nil
      assert order["spent"] > 0
      assert order["status"] == "filled"
      assert lots(s) == if(unquote(mode) == "fixed", do: 3, else: 5)
      s = until(s, c, &(ship(&1)["status"] == "sailing"), 100)
      assert Game.get(s, "companies", "company")["cash"] >= 0
    end
  end

  test "a tanker carrying refined fuel can plan a crude purchase after selling", c do
    vessel =
      ship(c.state)
      |> Map.merge(%{
        "class" => "tanker",
        "port" => "Ho Chi Minh City",
        "cargo" => [%{"good" => "refined_fuel", "quantity" => 3}]
      })

    s = State.put(c.state, "ships", vessel["id"], vessel)
    {:ok, s, _} = command(c, s, "hcm", %{"operation" => "add_stop", "port" => "Ho Chi Minh City"})

    {:ok, s, _} =
      command(c, s, "sell-fuel", %{
        "operation" => "add_rule",
        "stop" => "hcm",
        "side" => "sell",
        "good" => "refined_fuel",
        "quantity_mode" => "maximum",
        "limit" => 0
      })

    {:ok, s, _} =
      command(c, s, "buy-crude", %{
        "operation" => "add_rule",
        "stop" => "hcm",
        "side" => "buy",
        "good" => "crude_oil",
        "quantity_mode" => "maximum",
        "limit" => 100_000
      })

    model = TijaraTides.UseCases.GameQueries.route_editor(s.entities, vessel, c.catalogue)
    assert Enum.any?(model.stop_goods["hcm"]["buy"], &(elem(&1, 0) == "crude_oil"))
    refute Enum.any?(model.goods, &(elem(&1, 0) == "lumber"))
    assert Game.get(s, "route_rules", "buy-crude")["good"] == "crude_oil"

    refute TijaraTides.Domain.CargoRules.compatible_cargo?(
             vessel,
             c.catalogue["goods"]["crude_oil"]
           )

    assert TijaraTides.Domain.CargoRules.compatible_cargo?(
             %{vessel | "cargo" => []},
             c.catalogue["goods"]["crude_oil"]
           )
  end

  test "maximum rules accept no numeric quantity and reject unknown modes", c do
    {:ok, s, _} = command(c, c.state, "s1", %{"operation" => "add_stop", "port" => "Jakarta"})

    rule = %{
      "operation" => "add_rule",
      "stop" => "s1",
      "side" => "buy",
      "good" => "lumber",
      "quantity_mode" => "maximum",
      "limit" => 1_000_000,
      "budget" => 10_000_000
    }

    assert {:error, :instruction_quantity_invalid} =
             command(c, s, "bad", Map.put(rule, "quantity_mode", "other"))

    assert {:ok, updated, _} = command(c, s, "max", rule)
    assert Game.get(updated, "route_rules", "max")["quantity"] == nil
    assert Game.get(updated, "route_rules", "max")["quantity_mode"] == "maximum"
  end

  defp ship(s), do: Game.get(s, "ships", "company:1")
  defp plan(s), do: Game.get(s, "ship_routes", "company:1")
  defp lots(s), do: Enum.sum(for b <- ship(s)["cargo"], b["good"] == "lumber", do: b["quantity"])

  defp until(s, _c, predicate, 0),
    do:
      (
        assert predicate.(s),
               inspect(
                 {ship(s)["status"], lots(s), Game.entities(s, "ship_instructions"), plan(s)}
               )

        s
      )

  defp until(s, c, predicate, n) do
    if predicate.(s),
      do: s,
      else: until(Game.advance(s, 30_000, c.catalogue), c, predicate, n - 1)
  end

  test "a circuit sells before returning and resets targets without duplicate fills", c do
    s = route(c) |> ShipInstructions.advance(c.catalogue)
    assert ship(s)["status"] == "loading"
    assert lots(s) == 3
    again = ShipInstructions.advance(s, c.catalogue)
    assert again.journal == s.journal
    assert lots(again) == 3
    s = until(s, c, &(plan(&1)["visit"] >= 2), 100)
    assert ship(s)["destination"] == "Jakarta"
    assert lots(s) == 0
    s = until(s, c, &(plan(&1)["visit"] == 2 and ship(&1)["status"] == "loading"), 100)
    assert lots(s) == 3
    assert Game.get(s, "ship_instructions", "route:buy1")["filled"] == 3
  end

  test "pause drains handling and resume does not refill; stop after visit prevents departure",
       c do
    s = route(c) |> ShipInstructions.advance(c.catalogue)
    {:ok, s, _} = command(c, s, "pause", %{"operation" => "pause"})
    s = Game.advance(s, 300_000, c.catalogue)
    assert ship(s)["status"] == "docked"
    assert lots(s) == 3
    {:ok, s, _} = command(c, s, "resume", %{"operation" => "resume", "auto_depart" => true})
    {:ok, s, _} = command(c, s, "stop", %{"operation" => "stop_after"})
    s = ShipInstructions.advance(s, c.catalogue)
    assert plan(s)["status"] == "paused"
    assert ship(s)["status"] == "docked"
    assert lots(s) == 3
    {:ok, s, _} = command(c, s, "resume2", %{"operation" => "resume", "auto_depart" => true})
    s = ShipInstructions.advance(s, c.catalogue)
    assert ship(s)["status"] == "sailing"
    assert plan(s)["visit"] == 1
    assert lots(s) == 3
  end

  test "retained cargo counts toward load target; sale target is capped to cargo on arrival", c do
    s = route(c, false)

    s =
      State.put(
        s,
        "ships",
        "company:1",
        Map.put(ship(s), "cargo", [
          %{
            "lot_id" => "retained",
            "good" => "lumber",
            "quantity" => 2,
            "unit_cost" => 100,
            "expires_ms" => nil
          }
        ])
      )

    s = ShipInstructions.advance(s, c.catalogue)
    assert lots(s) == 3
    assert Game.get(s, "ship_instructions", "route:buy1")["quantity"] == 1
    s = Game.advance(s, 300_000, c.catalogue)
    assert ship(s)["status"] == "docked"
  end

  test "unfilled targets wait for a limit price and removal preserves cargo and handling", c do
    s = route(c)
    rule = Game.get(s, "route_rules", "buy1")

    s =
      State.put(s, "route_rules", "buy1", %{rule | "limit" => 0})
      |> ShipInstructions.advance(c.catalogue)

    assert ship(s)["status"] == "docked"
    assert Game.get(s, "ship_instructions", "route:buy1")["reason"] =~ "limit price"
    {:ok, s, _} = command(c, s, "delete", %{"operation" => "delete"})
    assert plan(s) == nil
    refute Enum.any?(Game.entities(s, "visit_plans"))
    s = route(c) |> ShipInstructions.advance(c.catalogue)
    {:ok, s, _} = command(c, s, "delete2", %{"operation" => "delete"})
    assert lots(s) == 3
    assert ship(s)["status"] == "loading"
    assert plan(s) == nil
  end

  test "ownership, editable active plans and valid circuits are enforced", c do
    s = route(c)

    assert {:error, :route_ship_not_owned} =
             ShipRoutes.execute(
               s,
               %{"company_id" => "other"},
               %{"ship" => "company:1", "operation" => "delete"},
               %{catalogue: c.catalogue}
             )

    assert {:ok, _, _} =
             command(c, s, "extra", %{"operation" => "add_stop", "port" => "Colombo"})

    assert {:error, :route_owns_instructions} =
             ShipInstructions.change_onward(
               s,
               c.account,
               "company:1",
               "Jakarta",
               "Singapore",
               c.catalogue,
               true
             )

    assert {:error, :ship_sale_unavailable} = Fleet.sell(s, c.account, "company:1", 0)
  end

  test "draft edits reject duplicate targets and normalize remaining stop positions", c do
    {:ok, s, _} = command(c, c.state, "a", %{"operation" => "add_stop", "port" => "Jakarta"})

    assert {:error, :route_needs_stops} =
             command(c, s, "start", %{"operation" => "start", "auto_depart" => true})

    assert {:error, :route_port_invalid} =
             command(c, s, "duplicate", %{"operation" => "add_stop", "port" => "Jakarta"})

    {:ok, s, _} = command(c, s, "b", %{"operation" => "add_stop", "port" => "Singapore"})

    rule = %{
      "operation" => "add_rule",
      "stop" => "b",
      "side" => "buy",
      "good" => "lumber",
      "quantity" => 3,
      "limit" => 100_000,
      "budget" => 1_000_000
    }

    {:ok, s, _} = command(c, s, "r", rule)
    assert {:error, :route_duplicate_rule} = command(c, s, "r2", rule)

    assert {:error, :instruction_quantity_invalid} =
             command(c, s, "bad", Map.put(rule, "quantity", 0))

    assert {:error, :instruction_budget_invalid} =
             command(c, s, "bad", Map.put(rule, "budget", 0))

    assert {:error, :instruction_cargo_invalid} =
             command(c, s, "bad", Map.put(rule, "good", "missing"))

    assert {:error, :route_port_invalid} = command(c, s, "bad", Map.put(rule, "stop", "missing"))
    {:ok, s, _} = command(c, s, "remove", %{"operation" => "remove_rule", "rule" => "r"})
    assert Game.get(s, "route_rules", "r") == nil
    {:ok, s, _} = command(c, s, "remove_stop", %{"operation" => "remove_stop", "stop" => "a"})
    assert [%{"position" => 0, "port" => "Singapore"}] = ShipRoutes.stops(s, "company:1")
  end

  test "an empty stop retries a blocked departure without spending or duplicating the leg", c do
    {:ok, s, _} = command(c, c.state, "a", %{"operation" => "add_stop", "port" => "Jakarta"})
    {:ok, s, _} = command(c, s, "b", %{"operation" => "add_stop", "port" => "Singapore"})
    {:ok, s, _} = command(c, s, "start", %{"operation" => "start", "auto_depart" => true})
    company = Game.get(s, "companies", c.account["company_id"])

    s =
      State.put(s, "companies", company["id"], %{company | "cash" => 0})
      |> ShipInstructions.advance(c.catalogue)

    assert ship(s)["status"] == "docked"
    assert Game.get(s, "visit_plans", "company:1|Jakarta")["departure_wait"] =~ "funds"
    s = State.put(s, "companies", company["id"], company) |> ShipInstructions.advance(c.catalogue)
    assert ship(s)["status"] == "sailing"
    assert plan(s)["visit"] == 1
    again = ShipInstructions.advance(s, c.catalogue)
    assert again.journal == s.journal
    assert plan(again)["visit"] == 1
  end

  test "a manual detour pauses the route and cannot resume at the wrong stop", c do
    s = route(c, false)
    q = Fleet.voyage_quote(ship(s), "Colombo", c.catalogue)
    {:ok, s, _} = Fleet.sail(s, c.account, "company:1", "Colombo", q["fuel"], c.catalogue)
    assert plan(s)["status"] == "paused"
    assert plan(s)["phase"] == "arrival"

    assert {:error, :route_start_port} =
             command(c, s, "resume", %{"operation" => "resume", "auto_depart" => true})

    assert Game.entities(s, "visit_plans") == %{}
  end

  test "full holds finish loading shortfalls, and finite budgets wait without exceeding their cap",
       c do
    s = route(c)
    rule = Game.get(s, "route_rules", "buy1")

    s =
      State.put(s, "route_rules", "buy1", %{rule | "quantity" => 10000, "budget" => 1_000_000_000})
      |> put_in([:entities, "companies", c.account["company_id"], "cash"], 1_000_000_000)
      |> put_in([:entities, "markets", "Jakarta|lumber", "stock"], 1000)
      |> ShipInstructions.advance(c.catalogue)

    s = until(s, c, &(ship(&1)["status"] == "sailing"), 100)
    assert lots(s) < 10000
    assert plan(s)["visit"] == 1
    s = route(c)
    rule = Game.get(s, "route_rules", "buy1")

    s =
      State.put(s, "route_rules", "buy1", %{rule | "budget" => 1})
      |> ShipInstructions.advance(c.catalogue)

    assert ship(s)["status"] == "docked"
    assert Game.get(s, "ship_instructions", "route:buy1")["reason"] =~ "cap exhausted"
  end
end
