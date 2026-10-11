defmodule TijaraTides.UseCases.AutomationProtectionTest do
  use ExUnit.Case, async: true

  alias TijaraTides.Domain.{
    Game,
    State,
    Fleet,
    ShipWorld,
    CompanyFinanceWorld,
    AutomationWorld,
    Journal,
    Trading,
    Markets,
    Visibility,
    Trade,
    Piracy
  }

  alias TijaraTides.Domain.Services.{DepartureFunding, RouteEditing, TradeSettlement}
  alias TijaraTides.UseCases.GameQueries

  setup do
    cat =
      TijaraTides.Infrastructure.GameCatalogue.all() |> Map.put("weather", %{"chance_bps" => 0})

    s = Game.initialize(%{entities: %{}, clock_ms: 0, epoch: 1, revision: 0}, cat)
    {:ok, s, _} = Game.seed_invite(s, "invite")
    {:ok, s, _} = Game.redeem(s, "invite", "session", %{id: "a", wall_ms: 0})

    {:ok, s, _} =
      TijaraTides.CompanyFixture.create_company(
        s,
        State.get(s, "accounts", "a"),
        "Protected route",
        "Tangier",
        "general",
        %{id: "co", catalogue: cat}
      )

    %{s: Journal.clear(s), cat: cat, a: State.get(s, "accounts", "a"), id: "co:1"}
  end

  defp edit(c, s, params, id \\ "edit") do
    {:ok, next, _} =
      RouteEditing.execute(s, c.a, Map.put(params, "ship", c.id), %{id: id, catalogue: c.cat})

    next
  end

  defp route(c, protection, destination \\ "Athens") do
    c.s
    |> then(&edit(c, &1, %{"operation" => "add_stop", "port" => "Tangier"}, "first"))
    |> then(&edit(c, &1, %{"operation" => "add_stop", "port" => destination}, "next"))
    |> then(&edit(c, &1, %{"operation" => "set_protection", "protection" => protection}))
    |> then(&edit(c, &1, %{"operation" => "start", "auto_depart" => true}))
    |> ShipWorld.prepare_visits(c.cat)
  end

  defp free(s, n) do
    company = State.get(s, "companies", "co")
    delta = n - company["cash"] + company["reserved"]

    CompanyFinanceWorld.post(s, "co", "test_funds", [
      {"cash_available", delta},
      {"capital", -delta}
    ])
  end

  defp quote(c, s, choice, destination \\ "Athens"),
    do:
      Fleet.automated_quote(
        State.get(s, "ships", c.id),
        destination,
        c.cat,
        s.clock_ms,
        nil,
        choice
      )

  defp cost(q), do: q["fuel"] + q["canal_fees"] + q["protection_quote"]["cost"]

  test "all route choices depart at exact funding and wait at one cent short", c do
    for choice <- ~w(none guards insurance both) do
      s = route(c, choice)
      q = quote(c, s, choice)
      needed = cost(q)
      waiting = free(s, needed - 1) |> DepartureFunding.advance(c.cat)
      request = State.get(waiting, "departure_requests", c.id)
      assert request["protection"] == choice
      assert request["required"] == needed
      assert State.get(waiting, "ships", c.id)["status"] == "docked"
      next = free(waiting, needed) |> DepartureFunding.advance(c.cat)
      assert State.get(next, "ships", c.id)["piracy"]["protection"] == choice
      assert State.get(next, "departure_requests", c.id) == nil

      assert State.get(next, "companies", "co")["cash"] -
               State.get(next, "companies", "co")["reserved"] == 0

      entries = Enum.flat_map(next.journal, & &1.entries)

      assert Enum.sum(for {"piracy_guard_expense", n} <- entries, do: n) ==
               q["protection_quote"]["guard_fee"]

      assert Enum.sum(for {"piracy_premium_expense", n} <- entries, do: n) ==
               q["protection_quote"]["premium"]

      TijaraTides.SettledCheck.assert_settled!(waiting, next, c.cat, "tick")
    end
  end

  test "safe legs retain the route preference and buy only applicable cover", c do
    for {choice, effective} <- [{"insurance", "none"}, {"both", "guards"}] do
      s = route(c, choice, "Valencia")
      q = quote(c, s, choice, "Valencia")
      assert q["protection_quote"]["cost"] == 0
      next = free(s, cost(q)) |> DepartureFunding.advance(c.cat)
      assert State.get(next, "ships", c.id)["status"] == "sailing"
      assert State.get(next, "ships", c.id)["piracy"]["protection"] == effective
      assert State.get(next, "ship_routes", c.id)["protection"] == choice
    end
  end

  test "editing protection leaves a waiting request and its reservations unchanged", c do
    s = route(c, "both") |> free(0) |> DepartureFunding.advance(c.cat)
    row = State.get(s, "departure_requests", c.id)
    s = free(s, 100)
    s = AutomationWorld.accumulate(s, row, 100, s.clock_ms + 600_000)
    old = State.get(s, "departure_requests", c.id)
    changed = edit(c, s, %{"operation" => "set_protection", "protection" => "none"})
    assert State.get(changed, "departure_requests", c.id) == old
    assert State.get(changed, "ship_routes", c.id)["protection"] == "none"
    changed = free(changed, old["required"] - 100) |> DepartureFunding.advance(c.cat)
    assert State.get(changed, "ships", c.id)["piracy"]["protection"] == "both"

    corrupt = State.put(s, "departure_requests", c.id, %{old | "protection" => "none"})

    assert_raise ArgumentError, ~r/request_protection_changed/, fn ->
      TijaraTides.SettledCheck.assert_settled!(s, corrupt, c.cat, "route")
    end

    for value <- [nil, "bogus", 1] do
      assert {:error, :departure_protection_invalid} =
               RouteEditing.execute(
                 s,
                 c.a,
                 %{"ship" => c.id, "operation" => "set_protection", "protection" => value},
                 %{id: "invalid", catalogue: c.cat}
               )
    end

    assert {:error, :route_missing} =
             RouteEditing.execute(
               c.s,
               c.a,
               %{"ship" => c.id, "operation" => "set_protection", "protection" => "both"},
               %{id: "missing", catalogue: c.cat}
             )

    assert State.get(c.s, "ship_routes", c.id) == nil
  end

  test "campaign announcements reprice waiting requests without resetting age or accumulation",
       c do
    # A long announced campaign covers the complete test voyage.
    model =
      c.cat["piracy"]
      |> Map.put("first_slot", 0)
      |> put_in(["campaign", "period_ms"], 4_000_000)
      |> put_in(["campaign", "duration_ms"], 2_000_000)
      |> put_in(["campaign", "warning_ms"], 100_000)
      |> put_in(["zones", "barbary_coast", "campaign_bps"], 10_000)

    # Search a deterministic seed whose announcement still lies ahead of clock zero.
    model =
      Enum.find_value(1..100, fn seed ->
        m = %{model | "seed" => seed}
        campaign = Piracy.campaign("barbary_coast", 0, m)
        if campaign["announced_ms"] > 0, do: m
      end)

    campaign = Piracy.campaign("barbary_coast", 0, model)
    c = %{c | cat: Map.put(c.cat, "piracy", model)}
    s = route(c, "insurance") |> free(0) |> DepartureFunding.advance(c.cat)
    row = State.get(s, "departure_requests", c.id)
    s = free(s, row["required"] - 1)
    s = AutomationWorld.accumulate(s, row, row["required"] - 1, 9_000_000)
    old = State.get(s, "departure_requests", c.id)
    # Advance only the clock; the request is repriced by the ordinary attempt path.
    s = %{s | clock_ms: campaign["starts_ms"]}
    q = quote(c, s, "insurance")
    assert cost(q) > old["required"]
    next = DepartureFunding.advance(s, c.cat)
    repriced = State.get(next, "departure_requests", c.id)
    assert repriced["required"] == cost(q)
    assert repriced["blocked_ms"] == old["blocked_ms"]
    assert repriced["window_deadline_ms"] == old["window_deadline_ms"]
    assert repriced["accumulated"] == old["accumulated"]
    assert State.get(next, "ships", c.id)["status"] == "docked"
    next = free(next, cost(q) - repriced["accumulated"]) |> DepartureFunding.advance(c.cat)
    assert State.get(next, "ships", c.id)["piracy"]["protection"] == "insurance"
  end

  test "lower requirements clamp accumulated cash and release the excess atomically", c do
    s = route(c, "insurance") |> free(0) |> DepartureFunding.advance(c.cat)
    row = State.get(s, "departure_requests", c.id)
    inflated = row["required"] + 10_000
    s = AutomationWorld.reprice_request(s, row, "wait", inflated)
    row = State.get(s, "departure_requests", c.id)
    s = free(s, inflated)
    s = AutomationWorld.accumulate(s, row, inflated, 900_000)
    # Revalidation follows a route transition, keeping identity and releasing excess.
    next = DepartureFunding.revalidate(s, [c.id], c.cat)
    repriced = State.get(next, "departure_requests", c.id)
    assert repriced["required"] == inflated - 10_000
    assert repriced["accumulated"] == repriced["required"]

    assert State.get(s, "companies", "co")["reserved"] -
             State.get(next, "companies", "co")["reserved"] == 10_000

    assert repriced["blocked_ms"] == row["blocked_ms"]
    assert repriced["window_deadline_ms"] == 900_000
  end

  test "reduced and skip funding protect voyage costs before allocating purchase budgets", c do
    for policy <- ~w(wait reduced skip), extra <- [0, 500] do
      s = route(c, "both")

      {:ok, s, _} =
        DepartureFunding.configure_visit(
          s,
          c.a,
          %{"ship" => c.id, "stop" => "next", "amount" => 1000},
          c.cat
        )

      {:ok, s, _} = DepartureFunding.set_policy(s, c.a, policy, c.cat)
      q = quote(c, s, "both")
      s = free(s, cost(q) + extra) |> DepartureFunding.advance(c.cat)

      if policy == "wait" do
        assert State.get(s, "ships", c.id)["status"] == "docked"
        assert State.get(s, "departure_requests", c.id)["required"] == cost(q) + 1000
      else
        assert State.get(s, "ships", c.id)["status"] == "sailing"
        budget = State.get(s, "visit_budgets", "next")
        assert budget["remaining"] == if(policy == "skip", do: 0, else: extra)
        assert budget["skip"] == (policy == "skip")
      end
    end
  end

  test "protected purchase offers fund the same onward costs the command enforces", c do
    s = route(c, "both")
    ship = State.get(s, "ships", c.id)
    q = Markets.quote(s, c.cat, "Tangier", "everyday_clothing")
    item = c.cat["goods"]["everyday_clothing"]

    voyage =
      Trading.purchase_voyage(
        ship,
        item,
        2,
        "Athens",
        Map.values(State.entities(s, "ships")),
        0,
        c.cat,
        "both"
      )

    assert voyage["required"] == cost(voyage) + voyage["upkeep"]
    total = Trading.purchase_total(q, ship, item, 2)
    s = free(s, total + voyage["required"])

    view = %{
      public: Visibility.public(s, c.cat),
      private: Visibility.private(s, c.a),
      markets: Markets.quotes(s, c.cat)
    }

    public = Map.put(c.cat, "piracy", Piracy.public_model(c.cat["piracy"]))

    assert GameQueries.trade_limits(view, ship, "Athens", public)[{"buy", "everyday_clothing"}] ==
             2

    trade = %Trade{
      side: "buy",
      ship_id: c.id,
      good: "everyday_clothing",
      quantity: 2,
      limit: q["ask"],
      destination: "Athens"
    }

    assert TradeSettlement.validate(s, c.a, trade, c.cat) == :ok

    assert {:error, {:purchase_voyage_funds, _, _, _}} =
             TradeSettlement.validate(free(s, total + voyage["required"] - 1), c.a, trade, c.cat)

    refute TradeSettlement.validate(s, c.a, %{trade | quantity: 3}, c.cat) == :ok
    assert voyage["protection_quote"]["cost"] > 0
  end

  test "owned-stock collection offers reserve protection and reject a one-cent shortfall", c do
    s = route(c, "both")
    good = "everyday_clothing"

    {:ok, s, _} =
      TijaraTides.Domain.WarehouseWorld.lease(
        s,
        c.a,
        %{
          "port" => "Tangier",
          "storage" => "dry",
          "blocks" => 5,
          "days" => 1,
          "price" =>
            TijaraTides.Domain.Warehouse.quote(
              TijaraTides.Domain.WarehouseWorld.used(s, "Tangier", "dry"),
              "dry",
              5,
              1
            )
        },
        "stock",
        c.cat
      )

    {s, lot} = TijaraTides.Domain.CargoLots.create(s, good, 10, nil)
    warehouse = State.get(s, "warehouses", "stock")
    batch = Map.merge(lot, %{"good" => good, "unit_cost" => 100, "expires_ms" => nil})
    s = State.put(s, "warehouses", "stock", %{warehouse | "cargo" => [batch]})

    s =
      CompanyFinanceWorld.post(s, "co", "purchase", [
        {"inventory", 1000},
        {"cash_available", -1000}
      ])

    ship = State.get(s, "ships", c.id)
    loaded = Map.update!(ship, "cargo", &(&1 ++ [%{"good" => good, "quantity" => 2}]))
    loading = TijaraTides.Domain.CargoRules.handling_ms(2, "Tangier", good, c.cat)
    q = Fleet.automated_quote(loaded, "Athens", c.cat, loading, 0, "both")
    fee = 2 * TijaraTides.Domain.PortCargoMarket.handling_rate(c.cat["ports"]["Tangier"])
    s = free(s, cost(q) + fee)

    view = %{
      public: Visibility.public(s, c.cat),
      private: Visibility.private(s, c.a),
      markets: Markets.quotes(s, c.cat)
    }

    public = Map.put(c.cat, "piracy", Piracy.public_model(c.cat["piracy"]))
    definitions = %{catalogue: public, classes: Fleet.classes()}

    model =
      GameQueries.instruction_editor(
        definitions,
        ship,
        %{"side" => "buy", "good" => good},
        view.markets,
        "Tangier",
        view.private["company"],
        view
      )

    assert model.maximum == 2

    trade = %Trade{
      side: "buy",
      ship_id: c.id,
      good: good,
      quantity: 2,
      limit: 1_000_000,
      destination: "Athens"
    }

    assert TijaraTides.Domain.Services.AutomatedVisits.validate(s, c.a, trade, c.cat) == :ok

    assert TijaraTides.Domain.Services.AutomatedVisits.validate(
             free(s, cost(q) + fee - 1),
             c.a,
             trade,
             c.cat
           ) == {:error, :insufficient_cash}

    assert TijaraTides.Domain.Services.AutomatedVisits.validate(
             s,
             c.a,
             %{trade | quantity: 3},
             c.cat
           ) == {:error, :insufficient_cash}
  end

  test "public instruction and purchase quantities remain admissible at campaign price boundaries",
       c do
    model =
      c.cat["piracy"]
      |> put_in(["campaign"], %{
        "period_ms" => 1_000_000,
        "duration_ms" => 400_000,
        "warning_ms" => 100_000,
        "multiplier" => 4
      })
      |> put_in(["zones", "barbary_coast", "campaign_bps"], 10_000)

    c = %{c | cat: Map.put(c.cat, "piracy", model)}
    s = route(c, "both")
    ship = State.get(s, "ships", c.id)
    item = c.cat["goods"]["everyday_clothing"]
    market = Markets.quote(s, c.cat, "Tangier", item["id"])
    fleet = Map.values(State.entities(s, "ships"))
    baseline = Trading.purchase_voyage(ship, item, 2, "Athens", fleet, 0, c.cat, "both")
    [{_, from, into}] = Piracy.crossings(c.cat["routes"]["Tangier|Athens"], model)
    midpoint = round(baseline["sailing_ms"] * (from + into) / 2)
    campaign = Piracy.campaign("barbary_coast", 2, model)
    public = Map.put(c.cat, "piracy", Piracy.public_model(model))

    for edge <- [campaign["starts_ms"], campaign["until_ms"]], delta <- [-1, 0, 1] do
      clock = edge - baseline["loading_ms"] - midpoint + delta
      s = %{s | clock_ms: clock}
      voyage = Trading.purchase_voyage(ship, item, 2, "Athens", fleet, clock, c.cat, "both")

      assert voyage ==
               Trading.purchase_voyage(ship, item, 2, "Athens", fleet, clock, public, "both")

      total = Trading.purchase_total(market, ship, item, 2)
      s = free(s, total + voyage["required"])

      view = %{
        public: Visibility.public(s, c.cat),
        private: Visibility.private(s, c.a),
        markets: Markets.quotes(s, c.cat)
      }

      assert GameQueries.trade_limits(view, ship, "Athens", public)[{"buy", item["id"]}] == 2

      editor =
        GameQueries.instruction_editor(
          %{catalogue: public, classes: Fleet.classes()},
          ship,
          %{"side" => "buy", "good" => item["id"]},
          view.markets,
          "Tangier",
          view.private["company"],
          view
        )

      assert editor.maximum == 2

      trade = %Trade{
        side: "buy",
        ship_id: c.id,
        good: item["id"],
        quantity: editor.maximum,
        limit: market["ask"],
        destination: "Athens"
      }

      assert TradeSettlement.validate(s, c.a, trade, c.cat) == :ok

      assert {:error, {:purchase_voyage_funds, _, _, _}} =
               TradeSettlement.validate(
                 free(s, total + voyage["required"] - 1),
                 c.a,
                 trade,
                 c.cat
               )

      refute TradeSettlement.validate(s, c.a, %{trade | quantity: 3}, c.cat) == :ok
    end
  end
end
