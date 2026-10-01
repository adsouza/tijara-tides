defmodule TijaraTides.Domain.RouteFundingTest do
  use ExUnit.Case, async: true

  alias TijaraTides.Domain.{
    Game,
    State,
    ShipWorld,
    WarehouseWorld,
    Warehouse,
    AutomationWorld,
    CompanyFinanceWorld,
    Fleet,
    CargoLots,
    OrderBookWorld,
    Visibility
  }

  alias TijaraTides.Domain.Services.{
    DepartureFunding,
    LinkedOrders,
    Exchange,
    AutomatedVisits,
    WarehouseLiquidation
  }

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

    a = State.get(s, "accounts", "a")

    {:ok, s, _} =
      WarehouseWorld.lease(
        s,
        a,
        %{
          "port" => "Jakarta",
          "storage" => "dry",
          "blocks" => 10,
          "days" => 1,
          "price" => Warehouse.quote(WarehouseWorld.used(s, "Jakarta", "dry"), "dry", 10, 1)
        },
        "w",
        cat
      )

    m = State.get(s, "markets", "Jakarta|lumber")
    s = State.put(s, "markets", "Jakarta|lumber", %{m | "stock" => 0, "demand" => 0})
    %{s: s, a: a, cat: cat}
  end

  defp route(c, s, ship \\ "co:1") do
    prefix = ship <> ":"
    s = edit(c, s, prefix <> "a", ship, %{"operation" => "add_stop", "port" => "Jakarta"})
    s = edit(c, s, prefix <> "b", ship, %{"operation" => "add_stop", "port" => "Singapore"})
    edit(c, s, "start", ship, %{"operation" => "start", "auto_depart" => true})
  end

  defp edit(c, s, id, ship, params) do
    {:ok, s, _} =
      TijaraTides.Domain.Services.RouteEditing.execute(s, c.a, Map.put(params, "ship", ship), %{
        id: id,
        catalogue: c.cat
      })

    s
  end

  defp link(c, s, n \\ 5, price \\ 100) do
    s = route(c, s)

    edit(c, s, "rule", "co:1", %{
      "operation" => "add_rule",
      "stop" => "co:1:a",
      "side" => "buy",
      "good" => "lumber",
      "quantity" => n,
      "limit" => price,
      "linked_warehouse_id" => "w"
    })
  end

  defp prepare(s, c), do: ShipWorld.prepare_visits(s, c.cat)

  defp free(s, n) do
    company = State.get(s, "companies", "co")
    delta = n - company["cash"] + company["reserved"]

    CompanyFinanceWorld.post(s, "co", "test_funds", [
      {"cash_available", delta},
      {"capital", -delta}
    ])
  end

  defp cash(s),
    do: State.get(s, "companies", "co")["cash"] - State.get(s, "companies", "co")["reserved"]

  defp config(c, s, ship, amount) do
    {:ok, s, _} =
      DepartureFunding.configure_visit(
        s,
        c.a,
        %{"ship" => ship, "stop" => ship <> ":b", "amount" => amount},
        c.cat
      )

    s
  end

  defp policy(c, s, value) do
    {:ok, s, _} = TijaraTides.Domain.AccountWorld.set_funding_policy(s, c.a, value)
    s
  end

  defp fuel_required(c, s, ship \\ "co:1") do
    q = Fleet.voyage_quote(State.get(s, "ships", ship), "Singapore", c.cat)
    q["fuel"] + q["canal_fees"]
  end

  test "route queries and commands agree on eligible receiving warehouses", c do
    s = route(c, c.s)
    w = State.get(s, "warehouses", "w")

    variants = [
      {"award", %{"award_grace" => true}},
      {"expired", %{"expires_ms" => 1}},
      {"foreign", %{"company_id" => "other"}},
      {"elsewhere", %{"port" => "Singapore"}},
      {"incompatible", %{"storage" => "liquid", "good" => "crude_oil"}},
      {"cooled", %{"storage" => "reefer"}}
    ]

    s =
      Enum.reduce(variants, s, fn {id, changes}, state ->
        State.put(state, "warehouses", id, Map.merge(w, Map.put(changes, "id", id)))
      end)

    s = %{s | clock_ms: 1}

    model =
      TijaraTides.UseCases.GameQueries.route_editor(
        s.entities,
        State.get(s, "ships", "co:1"),
        c.cat,
        s.clock_ms
      )

    assert Enum.map(model.link_warehouses["co:1:a"]["lumber"], &elem(&1, 0)) == ["cooled", "w"]

    assert {:error, :linked_order_invalid} =
             TijaraTides.Domain.Services.RouteEditing.execute(
               s,
               c.a,
               %{
                 "ship" => "co:1",
                 "operation" => "add_rule",
                 "stop" => "co:1:a",
                 "side" => "buy",
                 "good" => "lumber",
                 "quantity" => 1,
                 "limit" => 100,
                 "linked_warehouse_id" => "award"
               },
               %{id: "invalid-award", catalogue: c.cat}
             )

    assert State.entities(s, "exchange_orders") == %{}
  end

  test "manual departure commands coordinate the next visit budget with fuel atomically", c do
    s = route(c, c.s) |> then(&config(c, &1, "co:1", 1000))
    required = fuel_required(c, s)

    payload = %{
      "action" => "sail",
      "ship" => "co:1",
      "destination" => "Singapore",
      "fuel_limit" => 86_400_000
    }

    context = %{id: "manual", catalogue: c.cat}
    insufficient = free(s, required + 999)

    assert {:error, {:departure_funds, _, _, _}} =
             TijaraTides.Domain.Commands.execute(insufficient, c.a, payload, context)

    assert State.get(insufficient, "visit_budgets", "co:1:b") == nil
    assert State.get(insufficient, "ships", "co:1")["status"] == "docked"

    {:ok, funded, _} =
      TijaraTides.Domain.Commands.execute(free(s, required + 1000), c.a, payload, context)

    assert State.get(funded, "visit_budgets", "co:1:b")["remaining"] == 1000
    assert State.get(funded, "ships", "co:1")["status"] == "sailing"
    assert cash(funded) == 0
  end

  defp stock(s, warehouse, n) do
    {s, lot} = CargoLots.create(s, "lumber", n, nil)
    w = State.get(s, "warehouses", warehouse)

    s =
      State.put(s, "warehouses", warehouse, %{
        w
        | "cargo" => w["cargo"] ++ [Map.merge(lot, %{"good" => "lumber", "unit_cost" => 50})]
      })

    CompanyFinanceWorld.post(s, w["company_id"], "test_stock", [
      {"inventory", n * 50},
      {"cash_available", -n * 50}
    ])
  end

  test "linked demand has its own cash and compatible warehouse capacity", c do
    before = cash(c.s)
    s = link(c, c.s)
    link = State.get(s, "remote_links", "rule")
    assert OrderBookWorld.fetch(s, link["order_id"]).quantity == 5
    assert cash(s) == before - 500

    assert State.get(s, "warehouse_reservations", "exchange:" <> link["order_id"])["quantity"] ==
             5

    assert State.entities(s, "visit_budgets") == %{}
  end

  test "NPC fills are owned and earmarked and cannot become sell backing", c do
    m = State.get(c.s, "markets", "Jakarta|lumber")

    s =
      State.put(c.s, "markets", "Jakarta|lumber", %{m | "stock" => 10})
      |> then(&link(c, &1, 5, 1_000_000))

    l = State.get(s, "remote_links", "rule")
    assert l["filled"] == 5
    assert OrderBookWorld.fetch(s, l["order_id"]) == nil
    r = State.get(s, "warehouse_reservations", "linked:" <> l["order_id"])
    assert r["ship_id"] == "co:1" and r["stop_id"] == "co:1:a" and r["quantity"] == 5

    assert {:error, :insufficient_cargo} =
             Exchange.place(
               s,
               c.a,
               %{
                 "warehouse" => "w",
                 "good" => "lumber",
                 "side" => "sell",
                 "quantity" => 1,
                 "price" => 100
               },
               "sell",
               c.cat
             )
  end

  test "berth handover releases unfilled reservations exactly once without buying cargo", c do
    s = link(c, c.s)
    before = cash(s)
    s = ShipWorld.grant_berth(s, "co:1")
    assert cash(s) == before + 500
    assert State.get(s, "remote_links", "rule")["status"] == "handed_over"
    assert State.entities(s, "exchange_orders") == %{}
    assert State.get(s, "ships", "co:1")["cargo"] == []
    assert LinkedOrders.handover(s, "co:1") == s
  end

  test "linked target reductions preserve priority and increases reject atomically without funding",
       c do
    s = link(c, c.s)
    l = State.get(s, "remote_links", "rule")
    original = OrderBookWorld.fetch(s, l["order_id"])

    params = %{
      "operation" => "update_rule",
      "rule" => "rule",
      "stop" => "co:1:a",
      "side" => "buy",
      "good" => "lumber",
      "quantity" => 3,
      "limit" => 100,
      "linked_warehouse_id" => "w"
    }

    s = %{s | clock_ms: 10} |> then(&edit(c, &1, "edit", "co:1", params))
    reduced = OrderBookWorld.fetch(s, l["order_id"])
    assert reduced.quantity == 3 and reduced.priority_ms == original.priority_ms
    s = free(s, 0)

    assert {:error, :insufficient_cash} =
             TijaraTides.Domain.Services.RouteEditing.execute(
               s,
               c.a,
               Map.merge(params, %{"ship" => "co:1", "quantity" => 10}),
               %{id: "edit", catalogue: c.cat}
             )

    assert State.get(s, "route_rules", "rule")["quantity"] == 3
    assert OrderBookWorld.fetch(s, l["order_id"]) == reduced
  end

  test "removing a linked rule frees purchased collection claims without moving its goods", c do
    m = State.get(c.s, "markets", "Jakarta|lumber")

    s =
      State.put(c.s, "markets", "Jakarta|lumber", %{m | "stock" => 10})
      |> then(&link(c, &1, 5, 1_000_000))

    s = edit(c, s, "remove", "co:1", %{"operation" => "remove_rule", "rule" => "rule"})
    assert State.entities(s, "remote_links") == %{}
    assert State.entities(s, "warehouse_reservations") == %{}
    assert Enum.sum(for b <- State.get(s, "warehouses", "w")["cargo"], do: b["quantity"]) == 5
  end

  test "unlinked orders survive a linked handover and direct linked amendments are rejected", c do
    s = link(c, c.s)

    {:ok, s, _} =
      Exchange.place(
        s,
        c.a,
        %{
          "warehouse" => "w",
          "good" => "lumber",
          "side" => "buy",
          "quantity" => 2,
          "price" => 100
        },
        "unlinked",
        c.cat
      )

    l = State.get(s, "remote_links", "rule")

    assert {:error, :linked_order_managed} =
             Exchange.amend(
               s,
               c.a,
               %{"order" => l["order_id"], "quantity" => 10, "price" => 100},
               c.cat
             )

    s = LinkedOrders.handover(s, "co:1")
    assert OrderBookWorld.fetch(s, "unlinked").quantity == 2
  end

  test "available owned stock and cargo aboard lower initial remote demand", c do
    s = stock(c.s, "w", 2)
    {s, batch} = CargoLots.create(s, "lumber", 1, nil)
    ship = State.get(s, "ships", "co:1")

    s =
      State.put(s, "ships", ship["id"], %{
        ship
        | "cargo" => [Map.merge(batch, %{"good" => "lumber", "unit_cost" => 50})]
      })
      |> then(&link(c, &1))

    assert OrderBookWorld.fetch(s, State.get(s, "remote_links", "rule")["order_id"]).quantity == 2
  end

  test "remote links and funding details are private", c do
    s = link(c, c.s)
    private = Visibility.private(s, c.a)
    assert map_size(private["remote_links"]) == 1
    public = Visibility.public(s, c.cat)

    for key <- ~w(remote_links visit_budgets departure_requests route_rules),
        do: refute(Map.has_key?(public, key))

    refute inspect(public) =~ "linked_warehouse_id"
  end

  test "Wait reserves fuel and the full next-stop budget in one successful departure", c do
    s = route(c, c.s) |> then(&config(c, &1, "co:1", 10_000)) |> prepare(c)
    fuel = fuel_required(c, s)
    s = free(s, fuel + 10_000) |> DepartureFunding.advance(c.cat)
    assert State.get(s, "ships", "co:1")["status"] == "sailing"
    assert cash(s) == 0
    budget = State.get(s, "visit_budgets", "co:1:b")
    assert budget["remaining"] == 10_000 and budget["strict"] and not budget["skip"]
    assert State.entities(s, "departure_requests") == %{}
    again = DepartureFunding.advance(s, c.cat)
    assert again.journal == s.journal and again.entities == s.entities
  end

  test "Wait notifies once, retries automatically and preserves its waiting age", c do
    s = route(c, c.s) |> then(&config(c, &1, "co:1", 10_000)) |> prepare(c)
    fuel = fuel_required(c, s)
    s = free(s, fuel + 500) |> DepartureFunding.advance(c.cat)
    assert State.get(s, "ships", "co:1")["status"] == "docked"
    assert State.get(s, "departure_requests", "co:1")["blocked_ms"] == 0
    notices = State.entities(s, "notices")
    s = %{s | clock_ms: 100} |> DepartureFunding.advance(c.cat)
    assert State.entities(s, "notices") == notices
    assert State.get(s, "departure_requests", "co:1")["blocked_ms"] == 0
    s = free(s, fuel + 10_000) |> DepartureFunding.advance(c.cat)
    assert State.get(s, "ships", "co:1")["status"] == "sailing"
  end

  test "Reduced policy fully funds fuel and keeps even a zero purchase budget strict", c do
    for extra <- [0, 500] do
      s =
        route(c, c.s)
        |> then(&config(c, &1, "co:1", 10_000))
        |> then(&policy(c, &1, "reduced"))
        |> prepare(c)

      s = free(s, fuel_required(c, s) + extra) |> DepartureFunding.advance(c.cat)
      assert State.get(s, "ships", "co:1")["status"] == "sailing"
      row = State.get(s, "visit_budgets", "co:1:b")
      assert row["remaining"] == extra and row["strict"]
      refute row["skip"]
    end
  end

  test "Skip cancels only next-stop linked demand and released cash does not reverse the decision",
       c do
    s = route(c, c.s)

    {:ok, s, _} =
      WarehouseWorld.lease(
        s,
        c.a,
        %{
          "port" => "Singapore",
          "storage" => "dry",
          "blocks" => 10,
          "days" => 1,
          "price" => Warehouse.quote(WarehouseWorld.used(s, "Singapore", "dry"), "dry", 10, 1)
        },
        "next-w",
        c.cat
      )

    s =
      edit(c, s, "next-rule", "co:1", %{
        "operation" => "add_rule",
        "stop" => "co:1:b",
        "side" => "buy",
        "good" => "lumber",
        "quantity" => 5,
        "limit" => 100,
        "linked_warehouse_id" => "next-w"
      })

    s = config(c, s, "co:1", 10_000) |> then(&policy(c, &1, "skip")) |> prepare(c)
    fuel = fuel_required(c, s)
    s = free(s, fuel) |> DepartureFunding.advance(c.cat)
    assert State.get(s, "ships", "co:1")["status"] == "sailing"
    assert State.get(s, "remote_links", "next-rule")["status"] == "skipped"
    assert State.entities(s, "exchange_orders") == %{}
    assert cash(s) == 500
    assert State.get(s, "visit_budgets", "co:1:b")["skip"]
  end

  test "none of the policies depart without fully funded fuel", c do
    for p <- ["wait", "reduced", "skip"] do
      s =
        route(c, c.s)
        |> then(&config(c, &1, "co:1", 10_000))
        |> then(&policy(c, &1, p))
        |> prepare(c)

      s = free(s, fuel_required(c, s) - 1) |> DepartureFunding.advance(c.cat)
      assert State.get(s, "ships", "co:1")["status"] == "docked"
      assert State.entities(s, "visit_budgets") == %{}
    end
  end

  test "oldest affordable ships are funded in order; an expensive request does not block a cheaper one",
       c do
    s =
      route(c, c.s)
      |> then(&route(c, &1, "co:2"))
      |> then(&config(c, &1, "co:1", 100_000))
      |> then(&config(c, &1, "co:2", 100))
      |> prepare(c)

    s = free(s, fuel_required(c, s, "co:2") + 100) |> DepartureFunding.advance(c.cat)
    assert State.get(s, "ships", "co:1")["status"] == "docked"
    assert State.get(s, "ships", "co:2")["status"] == "sailing"
    assert State.entities(s, "departure_requests") |> Map.keys() == ["co:1"]
  end

  test "one oldest request accumulates, times out at a fixed deadline, and enters cooldown", c do
    cat =
      Map.put(c.cat, "departure_funding", %{
        "wait_ms" => 100,
        "window_ms" => 50,
        "cooldown_ms" => 200
      })

    c = %{c | cat: cat}

    s =
      route(c, c.s)
      |> then(&route(c, &1, "co:2"))
      |> then(&config(c, &1, "co:1", 100_000))
      |> then(&config(c, &1, "co:2", 100_000))
      |> prepare(c)
      |> free(100)

    s = DepartureFunding.advance(s, cat)
    s = %{s | clock_ms: 100} |> DepartureFunding.advance(cat)
    a = State.get(s, "departure_requests", "co:1")
    assert a["accumulated"] == 100 and a["window_deadline_ms"] == 150
    assert State.get(s, "departure_requests", "co:2")["window_deadline_ms"] == nil
    s = free(s, 10) |> Map.put(:clock_ms, 120) |> DepartureFunding.advance(cat)
    assert State.get(s, "departure_requests", "co:1")["window_deadline_ms"] == 150
    s = %{s | clock_ms: 150} |> DepartureFunding.advance(cat)
    a = State.get(s, "departure_requests", "co:1")
    assert a["accumulated"] == 0 and a["cooldown_ms"] == 350 and a["blocked_ms"] == 0

    assert Enum.any?(State.entities(s, "notices"), fn {_, n} -> n["code"] == "funding.timeout" end)
  end

  test "accumulated money converts once into fuel and purchase reservations", c do
    cat =
      Map.put(c.cat, "departure_funding", %{
        "wait_ms" => 100,
        "window_ms" => 50,
        "cooldown_ms" => 200
      })

    s = route(c, c.s) |> then(&config(c, &1, "co:1", 1000)) |> prepare(c) |> free(100)
    required = fuel_required(c, s) + 1000

    s =
      DepartureFunding.advance(s, cat) |> Map.put(:clock_ms, 100) |> DepartureFunding.advance(cat)

    assert State.get(s, "departure_requests", "co:1")["accumulated"] == 100
    s = free(s, required - 100) |> Map.put(:clock_ms, 120) |> DepartureFunding.advance(cat)
    assert State.get(s, "ships", "co:1")["status"] == "sailing"
    assert cash(s) == 0
    assert State.get(s, "visit_budgets", "co:1:b")["remaining"] == 1000
    assert State.entities(s, "departure_requests") == %{}
  end

  test "policy changes and route removal release accumulated and visit cash", c do
    cat =
      Map.put(c.cat, "departure_funding", %{
        "wait_ms" => 100,
        "window_ms" => 50,
        "cooldown_ms" => 200
      })

    s = route(c, c.s) |> then(&config(c, &1, "co:1", 1000)) |> prepare(c) |> free(100)

    s =
      DepartureFunding.advance(s, cat) |> Map.put(:clock_ms, 100) |> DepartureFunding.advance(cat)

    s = policy(c, s, "reduced") |> DepartureFunding.reconcile(cat)
    assert State.entities(s, "departure_requests") == %{} and cash(s) == 100
    s = free(s, fuel_required(c, s) + 1000) |> DepartureFunding.advance(cat)
    assert State.get(s, "visit_budgets", "co:1:b")["remaining"] == 1000
    s = edit(c, s, "delete", "co:1", %{"operation" => "delete"})
    assert State.entities(s, "visit_budgets") == %{}
    assert cash(s) == 1000
  end

  test "strict arrival budget does not spend sale proceeds or released linked-order cash", c do
    s = link(c, c.s, 3, 100) |> prepare(c)

    spec = %{
      id: "co:1:a",
      ship_id: "co:1",
      company_id: "co",
      stop_id: "co:1:a",
      port: "Jakarta",
      configured: 1,
      visit: 0
    }

    s = AutomationWorld.reserve_visit(s, spec, 1, false)
    s = ShipWorld.grant_berth(s, "co:1")
    m = State.get(s, "markets", "Jakarta|lumber")
    s = State.put(s, "markets", "Jakarta|lumber", %{m | "stock" => 10})
    s = AutomatedVisits.advance(s, c.cat)
    assert State.get(s, "ships", "co:1")["cargo"] == []
    assert State.get(s, "visit_budgets", "co:1:a")["remaining"] == 1
    assert State.get(s, "ship_instructions", "route:rule")["filled"] == 0
  end

  test "bankruptcy clears all automation cash and collection claims", c do
    s = link(c, c.s) |> prepare(c)

    spec = %{
      id: "co:1:a",
      ship_id: "co:1",
      company_id: "co",
      stop_id: "co:1:a",
      port: "Jakarta",
      configured: 100,
      visit: 0
    }

    s = AutomationWorld.reserve_visit(s, spec, 100, false)
    {:ok, s, _} = TijaraTides.Domain.Services.Bankruptcy.bankrupt(s, c.a, "forced")

    for kind <- ~w(visit_budgets departure_requests remote_links exchange_orders),
        do: assert(State.entities(s, kind) == %{})
  end

  defp seller(c, s) do
    s = State.put(s, "accounts", "b", %{c.a | "id" => "b", "company_id" => nil})

    {:ok, s, _} =
      TijaraTides.CompanyFixture.create_company(
        s,
        State.get(s, "accounts", "b"),
        "Seller",
        "Jakarta",
        "general",
        %{id: "seller", catalogue: c.cat}
      )

    b = State.get(s, "accounts", "b")

    {:ok, s, _} =
      WarehouseWorld.lease(
        s,
        b,
        %{
          "port" => "Jakarta",
          "storage" => "dry",
          "blocks" => 10,
          "days" => 1,
          "price" => Warehouse.quote(WarehouseWorld.used(s, "Jakarta", "dry"), "dry", 10, 1)
        },
        "seller-w",
        c.cat
      )

    {stock(s, "seller-w", 3), b}
  end

  test "player fills and receiver liquidation both earmark the original warehouse cargo", c do
    for liquidating <- [false, true] do
      s = link(c, c.s)
      {s, b} = seller(c, s)

      s =
        if liquidating do
          w = State.get(s, "warehouses", "seller-w")

          s =
            State.put(s, "warehouses", "seller-w", %{w | "expires_ms" => 1, "grace_ms" => 1})
            |> Map.put(:clock_ms, 2)

          s
          |> WarehouseLiquidation.prepare(WarehouseWorld.fetch(s, "seller-w"), c.cat)
          |> WarehouseLiquidation.advance("seller-w", c.cat)
        else
          {:ok, s, _} =
            Exchange.place(
              s,
              b,
              %{
                "warehouse" => "seller-w",
                "good" => "lumber",
                "side" => "sell",
                "quantity" => 3,
                "price" => 100
              },
              "seller-order",
              c.cat
            )

          s
        end

      l = State.get(s, "remote_links", "rule")
      assert l["filled"] == 3
      assert State.get(s, "warehouse_reservations", "linked:" <> l["order_id"])["quantity"] == 3
      assert OrderBookWorld.fetch(s, l["order_id"]).quantity == 2
      assert Enum.sum(for b <- State.get(s, "warehouses", "w")["cargo"], do: b["quantity"]) == 3
    end
  end

  test "Skip still collects owned cargo, but never purchases the shortfall", c do
    s = link(c, c.s, 5, 100) |> prepare(c) |> then(&stock(&1, "w", 2))

    spec = %{
      id: "co:1:a",
      ship_id: "co:1",
      company_id: "co",
      stop_id: "co:1:a",
      port: "Jakarta",
      configured: 0,
      visit: 0
    }

    route = State.get(s, "ship_routes", "co:1")
    s = State.put(s, "ship_routes", "co:1", %{route | "auto_depart" => false})
    s = AutomationWorld.reserve_visit(s, spec, 0, true) |> AutomatedVisits.advance(c.cat)
    assert Enum.sum(for b <- State.get(s, "ships", "co:1")["cargo"], do: b["quantity"]) == 2
    ship = State.get(s, "ships", "co:1")

    s =
      State.put(s, "ships", ship["id"], %{ship | "status" => "docked"})
      |> AutomatedVisits.advance(c.cat)

    assert State.get(s, "ship_instructions", "route:rule")["status"] == "cancelled"
    assert State.get(s, "ship_instructions", "route:rule")["filled"] == 2
    assert Enum.sum(for b <- State.get(s, "ships", "co:1")["cargo"], do: b["quantity"]) == 2
  end

  test "visit completion rearms one new circuit and does not replay its reservations", c do
    s = link(c, c.s) |> prepare(c) |> ShipWorld.grant_berth("co:1")
    s = ShipWorld.cancel_visit_order(s, "route:rule", "Cancelled by player", c.cat)
    s = DepartureFunding.finish_visits(s, c.cat)
    l = State.get(s, "remote_links", "rule")
    assert l["status"] == "active" and l["generation"] > 0 and l["filled"] == 0
    assert OrderBookWorld.fetch(s, l["order_id"]).quantity == 5
    assert State.get(s, "ship_routes", "co:1")["visit_finished"]
    assert DepartureFunding.finish_visits(s, c.cat) == s
    assert LinkedOrders.handover(s, "co:1") == s
  end

  test "a visit wait deadline prevents new remote fills before the berth", c do
    s = link(c, c.s) |> prepare(c)
    route = State.get(s, "ship_routes", "co:1")

    s =
      State.put(s, "ship_routes", "co:1", %{route | "wait_deadline_ms" => 10})
      |> Map.put(:clock_ms, 10)

    {s, b} = seller(c, s)

    {:ok, s, _} =
      Exchange.place(
        s,
        b,
        %{
          "warehouse" => "seller-w",
          "good" => "lumber",
          "side" => "sell",
          "quantity" => 3,
          "price" => 100
        },
        "seller-order",
        c.cat
      )

    assert State.get(s, "remote_links", "rule")["filled"] == 0
    s = ShipWorld.expire_route_waits(s, c.cat) |> LinkedOrders.advance(c.cat)
    assert State.get(s, "remote_links", "rule")["status"] != "active"
    assert OrderBookWorld.fetch(s, State.get(s, "remote_links", "rule")["order_id"]) == nil
  end

  test "collection fees do not spend strict purchase funds, and committed purchase spending cannot be resized away",
       c do
    s = route(c, c.s)

    spec = %{
      id: "co:1:a",
      ship_id: "co:1",
      company_id: "co",
      stop_id: "co:1:a",
      port: "Jakarta",
      configured: 100_000,
      visit: 0
    }

    s = AutomationWorld.reserve_visit(s, spec, 100_000, false)

    trade = %TijaraTides.Domain.Trade{
      side: "buy",
      ship_id: "co:1",
      good: "lumber",
      quantity: 1,
      limit: 1_000_000,
      destination: "Singapore"
    }

    m = State.get(s, "markets", "Jakarta|lumber")
    s = State.put(s, "markets", "Jakarta|lumber", %{m | "stock" => 10})
    before_cash = cash(s)
    {:ok, s, reply} = TijaraTides.Domain.Services.TradeSettlement.execute(s, c.a, trade, c.cat)
    budget = State.get(s, "visit_budgets", spec.id)
    assert budget["remaining"] == 100_000 - reply["spent"]
    assert cash(s) == before_cash

    assert {:error, :visit_budget_committed} =
             AutomationWorld.resize_visit(s, budget, reply["spent"] - 1)

    assert {:ok, resized} = AutomationWorld.resize_visit(s, budget, reply["spent"])
    assert State.get(resized, "visit_budgets", spec.id)["remaining"] == 0
  end

  test "bills are paid before cash accumulates", c do
    cat =
      Map.put(c.cat, "departure_funding", %{
        "wait_ms" => 100,
        "window_ms" => 50,
        "cooldown_ms" => 200
      })

    s =
      route(c, c.s)
      |> then(&config(c, &1, "co:1", 100_000))
      |> prepare(c)
      |> free(0)
      |> DepartureFunding.advance(cat)

    s =
      CompanyFinanceWorld.post(s, "co", "test_bill", [{"handling_expense", 50}, {"payables", -50}])
      |> CompanyFinanceWorld.operating_bill("co", 50, 0)

    s = free(s, 100) |> Map.put(:clock_ms, 100) |> DepartureFunding.advance(cat)
    assert State.get(s, "companies", "co")["unpaid"] == 0
    assert State.entities(s, "operating_bills") == %{}
    assert State.get(s, "departure_requests", "co:1")["accumulated"] == 50
  end

  test "current visit budgets reserve immediately and starting a draft funds only its first stop",
       c do
    s = edit(c, c.s, "co:1:a", "co:1", %{"operation" => "add_stop", "port" => "Jakarta"})
    s = edit(c, s, "co:1:b", "co:1", %{"operation" => "add_stop", "port" => "Singapore"})

    {:ok, s, _} =
      DepartureFunding.configure_visit(
        s,
        c.a,
        %{"ship" => "co:1", "stop" => "co:1:a", "amount" => 200},
        c.cat
      )

    s = config(c, s, "co:1", 300)
    assert State.entities(s, "visit_budgets") == %{}
    before = cash(s)
    s = edit(c, s, "start", "co:1", %{"operation" => "start", "auto_depart" => false})
    assert cash(s) == before - 200
    assert State.get(s, "visit_budgets", "co:1:a")["remaining"] == 200
    assert State.get(s, "visit_budgets", "co:1:b") == nil

    {:ok, s, _} =
      DepartureFunding.configure_visit(
        s,
        c.a,
        %{"ship" => "co:1", "stop" => "co:1:a", "amount" => 250},
        c.cat
      )

    assert cash(s) == before - 250
    s = edit(c, s, "resume", "co:1", %{"operation" => "resume", "auto_depart" => false})
    assert cash(s) == before - 250
  end

  test "unfunded initial visit rejects start and malformed budget commands return errors", c do
    s = edit(c, c.s, "co:1:a", "co:1", %{"operation" => "add_stop", "port" => "Jakarta"})
    s = edit(c, s, "co:1:b", "co:1", %{"operation" => "add_stop", "port" => "Singapore"})

    {:ok, s, _} =
      DepartureFunding.configure_visit(
        s,
        c.a,
        %{"ship" => "co:1", "stop" => "co:1:a", "amount" => 200},
        c.cat
      )

    s = free(s, 100)

    assert {:error, :insufficient_cash} =
             TijaraTides.Domain.Services.RouteEditing.execute(
               s,
               c.a,
               %{"ship" => "co:1", "operation" => "start"},
               %{
                 id: "start",
                 catalogue: c.cat
               }
             )

    assert State.get(s, "ship_routes", "co:1")["status"] == "draft"
    assert State.entities(s, "visit_budgets") == %{}

    assert {:error, :instruction_ship_not_owned} =
             DepartureFunding.configure_visit(s, c.a, %{}, c.cat)
  end

  test "maximum wait releases unused visit cash before berth assignment", c do
    s = route(c, c.s)

    {:ok, s, _} =
      DepartureFunding.configure_visit(
        s,
        c.a,
        %{"ship" => "co:1", "stop" => "co:1:a", "amount" => 200},
        c.cat
      )

    before = cash(s)
    r = State.get(s, "ship_routes", "co:1")

    s =
      State.put(s, "ship_routes", "co:1", %{r | "wait_timed_out" => true})
      |> DepartureFunding.reconcile(c.cat)

    assert State.get(s, "visit_budgets", "co:1:a") == nil
    assert cash(s) == before + 200
    assert State.get(s, "route_stops", "co:1:a")["advance_budget"] == 200
    assert DepartureFunding.reconcile(s, c.cat) == s
  end

  test "single instructions expiring before arrival release their budget", c do
    {:ok, s, _} =
      ShipWorld.add_instruction(
        c.s,
        c.a,
        %{
          "ship" => "co:1",
          "port" => "Singapore",
          "good" => "lumber",
          "side" => "buy",
          "quantity" => 1,
          "limit" => 100,
          "budget" => 200,
          "onward" => "Jakarta",
          "expires_in_ms" => 1
        },
        %{id: "single", catalogue: c.cat}
      )

    {:ok, s, _} =
      DepartureFunding.configure_visit(
        s,
        c.a,
        %{"ship" => "co:1", "port" => "Singapore", "amount" => 200},
        c.cat
      )

    {:ok, s, _} = Fleet.sail(s, c.a, "co:1", "Singapore", 86_400_000, c.cat)
    before = cash(s)

    s =
      %{s | clock_ms: 1}
      |> ShipWorld.expire_instructions(c.cat)
      |> DepartureFunding.reconcile(c.cat)

    assert State.get(s, "ships", "co:1")["status"] == "sailing"
    assert State.get(s, "visit_budgets", "co:1|Singapore") == nil
    assert cash(s) == before + 200
    assert DepartureFunding.reconcile(s, c.cat) == s
  end

  test "a link with no initial shortfall remains live if owned stock later leaves", c do
    s = stock(c.s, "w", 5) |> then(&link(c, &1))
    assert State.get(s, "remote_links", "rule")["status"] == "active"
    assert State.entities(s, "exchange_orders") == %{}
    # An independent player sale consumes previously free stock before collection.
    {:ok, s, _} =
      Exchange.place(
        s,
        c.a,
        %{
          "warehouse" => "w",
          "good" => "lumber",
          "side" => "sell",
          "quantity" => 5,
          "price" => 100
        },
        "independent",
        c.cat
      )

    s = LinkedOrders.advance(s, c.cat)
    link = State.get(s, "remote_links", "rule")
    assert OrderBookWorld.fetch(s, link["order_id"]).quantity == 5
  end

  test "an explicit budget increase clears a per-visit skip decision", c do
    s = route(c, c.s)

    spec = %{
      id: "co:1:a",
      ship_id: "co:1",
      company_id: "co",
      stop_id: "co:1:a",
      port: "Jakarta",
      configured: 100,
      visit: 0
    }

    s = AutomationWorld.reserve_visit(s, spec, 0, true)

    {:ok, s, _} =
      DepartureFunding.configure_visit(
        s,
        c.a,
        %{"ship" => "co:1", "stop" => "co:1:a", "amount" => 100},
        c.cat
      )

    assert State.get(s, "visit_budgets", "co:1:a")["remaining"] == 100
    refute State.get(s, "visit_budgets", "co:1:a")["skip"]
  end

  test "invalid linked target commands reject without reaching typed root construction", c do
    s = route(c, c.s)

    for params <- [
          %{"side" => "sell"},
          %{"quantity_mode" => "maximum"},
          %{"limit" => 0},
          %{"linked_warehouse_id" => 12}
        ] do
      command =
        Map.merge(
          %{
            "operation" => "add_rule",
            "ship" => "co:1",
            "stop" => "co:1:a",
            "side" => "buy",
            "good" => "lumber",
            "quantity" => 5,
            "limit" => 100,
            "linked_warehouse_id" => "w"
          },
          params
        )

      assert {:error, :linked_order_invalid} =
               TijaraTides.Domain.Services.RouteEditing.execute(s, c.a, command, %{
                 id: "invalid",
                 catalogue: c.cat
               })
    end

    assert State.entities(s, "route_rules") == %{}
    assert State.entities(s, "remote_links") == %{}
  end

  test "owned collection can use linked-order refunds at berth without reserving them twice", c do
    s = stock(c.s, "w", 2) |> then(&link(c, &1, 5, 100_000)) |> prepare(c) |> free(0)
    link = State.get(s, "remote_links", "rule")
    assert OrderBookWorld.fetch(s, link["order_id"]).quantity == 3

    trade = %TijaraTides.Domain.Trade{
      side: "buy",
      ship_id: "co:1",
      good: "lumber",
      quantity: 1,
      limit: 100_000,
      destination: "Singapore"
    }

    assert :ok == AutomatedVisits.validate(s, c.a, trade, c.cat)
    assert OrderBookWorld.fetch(s, link["order_id"]).quantity == 3
    changed = AutomatedVisits.advance(s, c.cat)
    assert State.get(changed, "ships", "co:1")["status"] == "loading"
    assert Enum.sum(for b <- State.get(changed, "ships", "co:1")["cargo"], do: b["quantity"]) == 2
    assert State.get(changed, "remote_links", "rule")["status"] == "handed_over"
    assert OrderBookWorld.fetch(changed, link["order_id"]) == nil
    assert cash(changed) > 0
    assert LinkedOrders.handover(changed, "co:1") == changed
  end

  test "perishable linked orders inherit and amend shelf-life requirements", c do
    m = State.get(c.s, "markets", "Jakarta|fruit")

    s =
      State.put(c.s, "markets", "Jakarta|fruit", %{
        m
        | "stock" => 0,
          "batches" => [],
          "demand" => 0
      })
      |> then(&route(c, &1))

    s =
      edit(c, s, "food-rule", "co:1", %{
        "operation" => "add_rule",
        "stop" => "co:1:a",
        "side" => "buy",
        "good" => "fruit",
        "quantity" => 5,
        "limit" => 100,
        "linked_warehouse_id" => "w",
        "min_remaining_ms" => 60_000
      })

    link = State.get(s, "remote_links", "food-rule")
    order = OrderBookWorld.fetch(s, link["order_id"])
    assert order.min_remaining_ms == 60_000

    s =
      edit(c, %{s | clock_ms: 1, revision: 1}, "change", "co:1", %{
        "operation" => "update_rule",
        "rule" => "food-rule",
        "stop" => "co:1:a",
        "side" => "buy",
        "good" => "fruit",
        "quantity" => 5,
        "limit" => 100,
        "linked_warehouse_id" => "w",
        "min_remaining_ms" => 90_000
      })

    updated = OrderBookWorld.fetch(s, link["order_id"])
    assert updated.min_remaining_ms == 90_000
    assert updated.priority_ms == 1
    assert State.get(s, "companies", "co")["reserved"] == 500
  end
end
