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

  defp route(c, auto \\ true, max_wait \\ nil) do
    {:ok, s, _} = command(c, c.state, "s1", %{"operation" => "add_stop", "port" => "Jakarta"})

    {:ok, s, _} =
      command(c, s, "wait", %{
        "operation" => "set_wait",
        "stop" => "s1",
        "max_wait_ms" => max_wait
      })

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

  test "freshness terms validate, snapshot qualifying cargo aboard and defer edits to future visits",
       c do
    c = %{c | state: put_in(c.state, [:entities, "ships", "company:1", "class"], "reefer")}
    state = route(c, false)

    terms = %{
      "operation" => "update_rule",
      "rule" => "buy1",
      "stop" => "s1",
      "side" => "buy",
      "good" => "fruit",
      "quantity" => 3,
      "limit" => 1_000_000,
      "min_remaining_ms" => 3_600_000
    }

    for value <- [-1, 2_592_000_001, nil, "60", false, 1.5] do
      assert {:error, :instruction_freshness_invalid} =
               command(c, state, "bad", Map.put(terms, "min_remaining_ms", value))
    end

    assert {:error, :instruction_freshness_invalid} =
             command(c, state, "bad", Map.put(terms, "side", "sell"))

    {:ok, state, _} = command(c, state, "fresh", terms)
    {state, old} = TijaraTides.Domain.CargoLots.create(state, "fruit", 2, 3_599_999)
    {state, fresh} = TijaraTides.Domain.CargoLots.create(state, "fruit", 1, 3_600_000)
    cargo = for lot <- [old, fresh], do: Map.merge(lot, %{"good" => "fruit", "unit_cost" => 100})
    state = put_in(state, [:entities, "ships", "company:1", "cargo"], cargo)
    prepared = TijaraTides.Domain.ShipWorld.prepare_visits(state, c.catalogue)
    assert Game.get(prepared, "ship_instructions", "route:buy1")["quantity"] == 2
    assert Game.get(prepared, "ship_instructions", "route:buy1")["min_remaining_ms"] == 3_600_000
    {:ok, edited, _} = command(c, prepared, "edit", Map.put(terms, "min_remaining_ms", 7_200_000))
    assert Game.get(edited, "route_rules", "buy1")["min_remaining_ms"] == 7_200_000
    unchanged = TijaraTides.Domain.ShipWorld.prepare_visits(edited, c.catalogue)
    assert Game.get(unchanged, "ship_instructions", "route:buy1")["min_remaining_ms"] == 3_600_000
    assert Game.get(unchanged, "ships", "company:1")["cargo"] == cargo
  end

  test "buy maximum waits when all stock fails its freshness requirement", c do
    c = %{c | state: put_in(c.state, [:entities, "ships", "company:1", "class"], "reefer")}
    state = route(c, false)

    {:ok, state, _} =
      command(c, state, "fresh", %{
        "operation" => "update_rule",
        "rule" => "buy1",
        "stop" => "s1",
        "side" => "buy",
        "good" => "fruit",
        "quantity_mode" => "maximum",
        "limit" => 1_000_000,
        "min_remaining_ms" => 14_400_000
      })

    {state, lot} = TijaraTides.Domain.CargoLots.create(state, "fruit", 3, 3_599_999)
    market = Game.get(state, "markets", "Jakarta|fruit")

    state =
      State.put(state, "markets", "Jakarta|fruit", %{market | "stock" => 3, "batches" => [lot]})

    waiting = ShipInstructions.advance(state, c.catalogue)
    order = Game.get(waiting, "ship_instructions", "route:buy1")
    assert order["status"] == "waiting"
    assert order["filled"] == 0
    assert order["reason"] =~ "minimum remaining shelf life"
    assert Game.get(waiting, "ships", "company:1")["cargo"] == []
    assert ShipInstructions.advance(waiting, c.catalogue) == waiting
  end

  test "wait limits validate ownership and bounds; edits preserve the current deadline", c do
    s = route(c, false, 60_000)
    assert plan(s)["visit_arrived_ms"] == 0
    assert plan(s)["wait_deadline_ms"] == 60_000

    for value <- [0, -1, 2_592_000_001, "60000", 1.5] do
      assert {:error, :route_wait_invalid} =
               command(c, s, "bad", %{
                 "operation" => "set_wait",
                 "stop" => "s1",
                 "max_wait_ms" => value
               })
    end

    for stop <- ["missing", "foreign"] do
      foreign =
        State.put(s, "route_stops", "foreign", %{
          "id" => "foreign",
          "ship_id" => "other",
          "company_id" => "other",
          "position" => 0,
          "port" => "Jakarta"
        })

      assert {:error, :route_port_invalid} =
               command(c, foreign, "bad", %{
                 "operation" => "set_wait",
                 "stop" => stop,
                 "max_wait_ms" => nil
               })
    end

    {:ok, changed, _} =
      command(c, s, "clear", %{"operation" => "set_wait", "stop" => "s1", "max_wait_ms" => nil})

    assert Game.get(changed, "route_stops", "s1")["max_wait_ms"] == nil
    assert plan(changed)["wait_deadline_ms"] == 60_000

    {:ok, changed, _} =
      command(c, changed, "max", %{
        "operation" => "set_wait",
        "stop" => "s1",
        "max_wait_ms" => 2_592_000_000
      })

    assert Game.get(changed, "route_stops", "s1")["max_wait_ms"] == 2_592_000_000
    assert plan(changed)["wait_deadline_ms"] == 60_000
    assert plan(route(c))["wait_deadline_ms"] == nil
  end

  test "deadline wins against newly fillable targets, does not repeat notices, and preserves funding blocks",
       c do
    s = route(c, true, 60_000)
    market = Game.get(s, "markets", "Jakarta|lumber")

    s =
      State.put(s, "markets", "Jakarta|lumber", %{market | "stock" => 0})
      |> ShipInstructions.advance(c.catalogue)

    assert Game.get(s, "ship_instructions", "route:buy1")["status"] == "waiting"
    before = %{s | clock_ms: 59_999} |> ShipInstructions.advance(c.catalogue)
    assert lots(before) == 0
    refute plan(before)["wait_timed_out"]
    company = Game.get(before, "companies", "company")
    s = State.put(before, "companies", "company", %{company | "cash" => 0})
    s = State.put(s, "markets", "Jakarta|lumber", market)
    s = %{s | clock_ms: 60_000} |> ShipInstructions.advance(c.catalogue)
    assert lots(s) == 0
    assert plan(s)["wait_timed_out"]
    assert Game.get(s, "ship_instructions", "route:buy1")["status"] == "cancelled"
    assert Game.get(s, "visit_plans", "company:1|Jakarta")["departure_wait"] =~ "funds"
    again = ShipInstructions.advance(s, c.catalogue)
    assert again.entities["notices"] == s.entities["notices"]
    assert again.journal == s.journal
    s = State.put(s, "companies", "company", company) |> ShipInstructions.advance(c.catalogue)
    assert ship(s)["status"] == "sailing"
    assert plan(s)["visit_arrived_ms"] == nil
    assert plan(s)["wait_deadline_ms"] == nil
    assert plan(s)["visit"] == 1
    assert lots(s) == 0
    notice = Game.get(s, "notices", "route-timeout:company:1")
    assert [%{"filled" => 0, "quantity" => 3}] = notice["arguments"]["shortfalls"]
    view = TijaraTides.Domain.Visibility.private(s, c.account)
    model = TijaraTides.UseCases.GameQueries.route_editor(view, ship(s), c.catalogue)
    assert model.last_timeout == notice
  end

  test "timeout during a partial load drains handling without another fill", c do
    s = route(c, true, 500)
    market = Game.get(s, "markets", "Jakarta|lumber")

    s =
      State.put(s, "markets", "Jakarta|lumber", %{market | "stock" => 1})
      |> ShipInstructions.advance(c.catalogue)

    assert lots(s) == 1
    assert ship(s)["status"] == "loading"
    s = State.put(s, "markets", "Jakarta|lumber", market) |> Game.advance(500, c.catalogue)
    assert ship(s)["status"] == "loading"
    assert lots(s) == 1
    assert plan(s)["wait_timed_out"]
    assert Game.get(s, "ship_instructions", "route:buy1")["filled"] == 1
    assert Game.get(s, "ship_instructions", "route:buy1")["status"] == "cancelled"
    s = Game.advance(s, 500, c.catalogue)
    assert ship(s)["status"] == "sailing"
    assert lots(s) == 1

    assert [%{"filled" => 1, "quantity" => 3}] =
             Game.get(s, "notices", "route-timeout:company:1")["arguments"]["shortfalls"]
  end

  test "timeout during unloading records unstarted buys and never starts loading", c do
    s = route(c, true, 500)
    vessel = ship(s)

    s =
      State.put(
        s,
        "ships",
        vessel["id"],
        Map.put(vessel, "cargo", [
          %{
            "lot_id" => "retained",
            "good" => "lumber",
            "quantity" => 1,
            "unit_cost" => 100,
            "expires_ms" => nil
          }
        ])
      )

    {:ok, s, _} =
      command(c, s, "sell-first", %{
        "operation" => "add_rule",
        "stop" => "s1",
        "side" => "sell",
        "good" => "lumber",
        "quantity" => 1,
        "limit" => 0
      })

    market = Game.get(s, "markets", "Jakarta|lumber")

    s =
      State.put(s, "markets", "Jakarta|lumber", %{
        market
        | "buyer" => true,
          "demand" => 500,
          "budget" => 100_000_000
      })

    s = ShipInstructions.advance(s, c.catalogue)
    assert ship(s)["status"] == "unloading"
    refute Game.get(s, "ship_instructions", "route:buy1")
    s = Game.advance(s, 500, c.catalogue)
    assert ship(s)["status"] == "unloading"
    assert Game.get(s, "ship_instructions", "route:buy1")["status"] == "cancelled"
    assert Game.get(s, "ship_instructions", "route:buy1")["filled"] == 0
    s = Game.advance(s, 500, c.catalogue)
    assert ship(s)["status"] == "sailing"
    assert lots(s) == 0
    refute Enum.any?(s.journal, &(&1.kind == "purchase"))
  end

  test "arrival captures the real port arrival and expiry precedes berth admission on a coarse tick",
       c do
    s = route(c)

    {:ok, s, _} =
      command(c, s, "wait2", %{"operation" => "set_wait", "stop" => "s2", "max_wait_ms" => 1000})

    s = until(s, c, &(ship(&1)["status"] == "sailing"), 100)
    arrival = ship(s)["arrive_ms"]
    assert plan(s)["visit_arrived_ms"] == nil
    s = Game.advance(s, arrival - s.clock_ms + 1000, c.catalogue)
    # No unloading starts at the inclusive deadline, despite an available berth.
    assert ship(s)["status"] == "sailing"
    assert ship(s)["destination"] == "Jakarta"
    assert lots(s) == 3
    notice = Game.get(s, "notices", "route-timeout:company:1")
    assert notice["arguments"]["port"] == "Singapore"

    assert [%{"side" => "sell", "quantity" => 3, "filled" => 0}] =
             notice["arguments"]["shortfalls"]
  end

  test "berth retries, phase changes and pause/resume do not extend a visit", c do
    s = route(c, false, 60_000)
    s = TijaraTides.Domain.BerthFixture.update(s, "company:1", berth_retry_ms: 300_000)
    s = ShipInstructions.advance(s, c.catalogue)
    assert Game.get(s, "ship_instructions", "route:buy1")["reason"] == "Waiting for a berth"
    {:ok, s, _} = command(c, s, "pause", %{"operation" => "pause"})
    s = Game.advance(s, 60_000, c.catalogue)
    assert plan(s)["status"] == "paused"
    assert plan(s)["wait_timed_out"]
    assert plan(s)["wait_deadline_ms"] == 60_000
    {:ok, s, _} = command(c, s, "resume", %{"operation" => "resume"})
    s = ShipInstructions.advance(s, c.catalogue)
    assert ship(s)["status"] == "sailing"
    assert lots(s) == 0
  end

  test "completed targets do not time out while waiting for departure funding", c do
    s = route(c, false, 60_000) |> ShipInstructions.advance(c.catalogue)
    s = Game.advance(s, 100_000, c.catalogue)
    assert lots(s) == 3
    refute plan(s)["wait_timed_out"]
    assert plan(s)["visit_arrived_ms"] == 0
    assert Game.get(s, "notices", "route-timeout:company:1") == nil
  end

  test "starting a route while sailing leaves the timer unset until arrival", c do
    q = Fleet.voyage_quote(ship(c.state), "Singapore", c.catalogue)
    {:ok, s, _} = Fleet.sail(c.state, c.account, "company:1", "Singapore", q["fuel"], c.catalogue)
    {:ok, s, _} = command(c, s, "a", %{"operation" => "add_stop", "port" => "Singapore"})
    {:ok, s, _} = command(c, s, "b", %{"operation" => "add_stop", "port" => "Jakarta"})

    {:ok, s, _} =
      command(c, s, "wait", %{"operation" => "set_wait", "stop" => "a", "max_wait_ms" => 60_000})

    {:ok, s, _} = command(c, s, "start", %{"operation" => "start", "auto_depart" => false})
    assert plan(s)["visit_arrived_ms"] == nil
    assert plan(s)["wait_deadline_ms"] == nil
    arrival = ship(s)["arrive_ms"]
    s = Game.advance(s, arrival - s.clock_ms + 1, c.catalogue)
    assert plan(s)["visit_arrived_ms"] == arrival
    assert plan(s)["wait_deadline_ms"] == arrival + 60_000
  end

  test "an empty visit arriving after its deadline completes without a shortfall notice", c do
    s = route(c, false, 1000)
    {:ok, s, _} = command(c, s, "remove-buy", %{"operation" => "remove_rule", "rule" => "buy1"})
    s = Game.advance(s, 1000, c.catalogue)
    refute plan(s)["wait_timed_out"]
    assert Game.get(s, "notices", "route-timeout:company:1") == nil
    assert Game.get(s, "visit_plans", "company:1|Jakarta")
  end

  test "stop-after-visit also stops after a timeout, and the next circuit uses a fresh limit",
       c do
    s = route(c, true, 1000)
    rule = Game.get(s, "route_rules", "buy1")
    s = State.put(s, "route_rules", "buy1", %{rule | "limit" => 0})
    {:ok, s, _} = command(c, s, "stop", %{"operation" => "stop_after"})
    s = Game.advance(s, 1000, c.catalogue)
    assert plan(s)["status"] == "paused"
    assert lots(s) == 0

    {:ok, s, _} =
      command(c, s, "next-limit", %{
        "operation" => "set_wait",
        "stop" => "s1",
        "max_wait_ms" => 5000
      })

    {:ok, s, _} = command(c, s, "resume", %{"operation" => "resume"})
    s = ShipInstructions.advance(s, c.catalogue)
    s = until(s, c, &(plan(&1)["visit"] == 2), 100)
    s = Game.advance(s, ship(s)["arrive_ms"] - s.clock_ms, c.catalogue)
    assert plan(s)["wait_deadline_ms"] == plan(s)["visit_arrived_ms"] + 5000
    refute plan(s)["wait_timed_out"]
    assert Game.get(s, "ship_instructions", "route:buy1")["filled"] == 0
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

  test "future stop edits preserve the active cursor and committed stop removal resets the route",
       c do
    s = route(c)
    {:ok, s, _} = command(c, s, "s3", %{"operation" => "add_stop", "port" => "Colombo"})

    for id <- ["s1", "s2"] do
      {:ok, edited, _} = command(c, s, "remove", %{"operation" => "remove_stop", "stop" => id})
      assert plan(edited)["status"] == "draft"
      assert plan(edited)["cursor"] == 0
      refute Enum.any?(ShipRoutes.stops(edited, "company:1"), &(&1["id"] == id))
    end

    {:ok, s, _} = command(c, s, "remove", %{"operation" => "remove_stop", "stop" => "s3"})
    assert plan(s)["cursor"] == 0
    assert length(ShipRoutes.stops(s, "company:1")) == 2
  end

  for status <- ["loading", "sailing"] do
    test "removing an active stop preserves committed #{status}", c do
      state = until(route(c), c, &(ship(&1)["status"] == unquote(status)), 100)
      before = ship(state)

      {:ok, edited, _} =
        command(c, state, "remove", %{"operation" => "remove_stop", "stop" => "s2"})

      assert ship(edited) == before
      assert plan(edited)["status"] == "draft"
      assert length(ShipRoutes.stops(edited, "company:1")) == 1
      refute Game.get(edited, "ship_instructions", "route:buy1")
      refute Game.get(edited, "visit_plans", "company:1|Jakarta")
      assert {:error, :route_needs_stops} = command(c, edited, "start", %{"operation" => "start"})
    end
  end

  test "generated route edits keep an active cursor valid and preserve physical work", c do
    for seed <- 1..5 do
      rng = :rand.seed_s(:exsss, {seed, 97, 31})

      Enum.reduce(1..40, {route(c), rng}, fn step, {state, rng} ->
        {choice, rng} = :rand.uniform_s(4, rng)
        stops = ShipRoutes.stops(state, "company:1")

        params =
          case choice do
            1 ->
              %{
                "operation" => "add_stop",
                "port" => Enum.at(["Jakarta", "Singapore", "Colombo"], rem(step, 3))
              }

            2 ->
              %{
                "operation" => "remove_stop",
                "stop" =>
                  if(stops == [],
                    do: "missing",
                    else: Enum.at(stops, rem(step, length(stops)))["id"]
                  )
              }

            3 ->
              %{"operation" => "pause"}

            4 ->
              %{"operation" => "resume"}
          end

        next =
          case command(c, state, "generated:#{step}", params) do
            {:ok, next, _} -> next
            {:error, _} -> state
          end

        assert ship(next) == ship(state)
        updated = ShipRoutes.stops(next, "company:1")
        assert Enum.map(updated, & &1["position"]) == Enum.to_list(0..(length(updated) - 1)//1)

        if plan(next)["status"] != "draft" do
          assert length(updated) >= 2
          assert plan(next)["cursor"] in 0..(length(updated) - 1)
        end

        {next, rng}
      end)
    end
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
