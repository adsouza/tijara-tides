defmodule TijaraTides.UseCases.InstructionOffersTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias TijaraTides.Domain.{
    CargoLots,
    CompanyFinanceWorld,
    Fleet,
    Game,
    Markets,
    ShipWorld,
    State,
    Trade,
    Visibility
  }

  alias TijaraTides.Domain.Services.AutomatedVisits
  alias TijaraTides.UseCases.GameQueries

  setup do
    definitions = TijaraTides.UseCases.Game.definitions()

    s =
      Game.initialize(%{entities: %{}, clock_ms: 0, epoch: 1, revision: 0}, definitions.catalogue)

    {:ok, s, _} = Game.seed_invite(s, "invite")
    {:ok, s, _} = Game.redeem(s, "invite", "session", %{id: "a", wall_ms: 0})

    {:ok, s, _} =
      TijaraTides.CompanyFixture.create_company(
        s,
        Game.get(s, "accounts", "a"),
        "Offers",
        "Singapore",
        "general",
        %{id: "aco", catalogue: definitions.catalogue}
      )

    {:ok, s, _} =
      ShipWorld.change_onward(
        s,
        account(s),
        "aco:1",
        "Jakarta",
        "Singapore",
        definitions.catalogue,
        true
      )

    %{s: s, definitions: definitions, cat: definitions.catalogue}
  end

  defp account(s), do: Game.get(s, "accounts", "a")
  defp ship(s), do: Game.get(s, "ships", "aco:1")

  defp available(s, cash) do
    company = Game.get(s, "companies", "aco")
    delta = cash - company["cash"] + company["reserved"]

    CompanyFinanceWorld.post(s, "aco", "test_funds", [
      {"cash_available", delta},
      {"capital", -delta}
    ])
  end

  defp cargo(s, good, n) do
    {s, lot} = CargoLots.create(s, good, n, nil)

    batch =
      lot
      |> Map.merge(%{"good" => good, "unit_cost" => 100, "expires_ms" => nil})
      |> TijaraTides.Domain.Ship.CargoRows.decode()
      |> TijaraTides.Domain.Ship.CargoRows.encode()

    s
    |> State.put("ships", "aco:1", %{ship(s) | "cargo" => [batch]})
    |> CompanyFinanceWorld.post("aco", "purchase", [
      {"inventory", n * 100},
      {"cash_available", -n * 100}
    ])
  end

  defp warehouse(c, s, id, quantity) do
    {:ok, s, _} =
      TijaraTides.Domain.WarehouseWorld.lease(
        s,
        account(s),
        %{
          "port" => "Jakarta",
          "storage" => "dry",
          "blocks" => 1,
          "days" => 1,
          "price" =>
            TijaraTides.Domain.Warehouse.quote(
              TijaraTides.Domain.WarehouseWorld.used(s, "Jakarta", "dry"),
              "dry",
              1,
              1
            )
        },
        id,
        c.cat
      )

    {s, lot} = CargoLots.create(s, "lumber", quantity, nil)

    batch =
      lot
      |> Map.merge(%{"good" => "lumber", "unit_cost" => 100, "expires_ms" => nil})
      |> TijaraTides.Domain.Ship.CargoRows.decode()
      |> TijaraTides.Domain.Ship.CargoRows.encode()

    row = Game.get(s, "warehouses", id)

    s
    |> State.put("warehouses", id, %{row | "cargo" => [batch]})
    |> CompanyFinanceWorld.post("aco", "purchase", [
      {"inventory", quantity * 100},
      {"cash_available", -quantity * 100}
    ])
  end

  defp editor(c, s, draft \\ %{}, at_port \\ true) do
    s = if at_port, do: at_visit(s), else: s

    v = %{
      public: Visibility.public(s, c.cat),
      private: Visibility.private(s, account(s)),
      markets: Markets.quotes(s, c.cat)
    }

    GameQueries.instruction_editor(
      c.definitions,
      ship(s),
      Map.merge(%{"side" => "buy", "good" => "lumber"}, draft),
      v.markets,
      "Jakarta",
      v.private["company"],
      v
    )
  end

  # Isolate the visit from inbound travel, replenishment and other players. The
  # suggestion promises feasibility in this snapshot, not a future reservation.
  defp at_visit(s),
    do: State.put(s, "ships", "aco:1", %{ship(s) | "port" => "Jakarta", "status" => "docked"})

  defp trade(c, s, offer, overrides \\ %{}) do
    struct!(
      Trade,
      Map.merge(
        %{
          side: offer.side,
          ship_id: "aco:1",
          good: offer.good,
          quantity: offer.quantity,
          limit: offer.limit |> Decimal.new() |> Decimal.mult(100) |> Decimal.to_integer(),
          destination: "Singapore"
        },
        overrides
      )
    )
    |> then(&{&1, AutomatedVisits.validate(at_visit(s), account(s), &1, c.cat)})
  end

  defp fill(c, s, offer, draft \\ %{}) do
    params =
      Map.merge(
        %{
          "ship" => "aco:1",
          "port" => "Jakarta",
          "side" => offer.side,
          "good" => offer.good,
          "quantity" => offer.quantity,
          "limit" => offer.limit |> Decimal.new() |> Decimal.mult(100) |> Decimal.to_integer(),
          "budget" => String.to_integer(offer.budget) * 100,
          "onward" => "Singapore"
        },
        draft
      )

    {:ok, s, _} =
      ShipWorld.add_instruction(s, account(s), params, %{id: "offer", catalogue: c.cat})

    loaded = s |> at_visit() |> AutomatedVisits.advance(c.cat)
    assert %{"filled" => n, "status" => "filled"} = Game.get(loaded, "ship_instructions", "offer")
    assert n == offer.quantity
    loaded
  end

  test "the cash-bound default fills completely and sails after loading", c do
    s = available(c.s, 1_000_000)
    offer = editor(c, s)
    assert offer.quantity == 43
    assert editor(c, s, %{"freshness_minutes" => ""}) == offer
    assert {_, :ok} = trade(c, s, offer)
    assert {_, {:error, _}} = trade(c, s, offer, %{quantity: offer.quantity + 1})
    loaded = fill(c, s, offer)
    assert ship(loaded)["status"] == "loading"

    finished =
      Fleet.advance(%{loaded | clock_ms: ship(loaded)["arrive_ms"]}, 0)
      |> AutomatedVisits.advance(c.cat)

    assert ship(finished)["status"] == "sailing"
    assert ship(finished)["destination"] == "Singapore"
  end

  test "the suggestion reserves known inbound costs and agrees while already sailing", c do
    s = available(c.s, 50_000)
    offer = editor(c, s, %{}, false)
    assert offer.quantity > 0
    quote = Fleet.voyage_quote(ship(s), "Jakarta", c.cat, 0, 0)

    {:ok, moving, _} =
      Game.execute(
        s,
        account(s),
        %{
          "action" => "sail",
          "ship" => "aco:1",
          "destination" => "Jakarta",
          "fuel_limit" => quote["fuel"]
        },
        %{},
        c.cat
      )

    underway = editor(c, moving, %{}, false)
    # Reserved fuel must not be charged twice when editing an in-flight visit.
    assert underway.quantity == offer.quantity
    assert underway.budget == offer.budget
    assert editor(c, available(c.s, 30_000), %{}, false).quantity == 0
    assert editor(c, available(c.s, quote["fuel"]), %{}, false).quantity == 0
  end

  test "retained cargo uses remaining hold space, not the empty hull's capacity", c do
    s = c.s |> cargo("iron_ore", 499) |> available(100_000_000)
    offer = editor(c, s)
    assert offer.quantity == 2
    assert {_, :ok} = trade(c, s, offer)
    assert {_, {:error, :capacity_exceeded}} = trade(c, s, offer, %{quantity: 3})
    fill(c, s, offer)
  end

  test "purchase caps, limit prices, unpaid costs and unavailable voyages withhold unfillable suggestions",
       c do
    s = available(c.s, 1_000_000)
    capped = editor(c, s, %{"budget" => "500"})
    assert capped.quantity > 0 and capped.quantity < editor(c, s).quantity
    fill(c, s, capped)
    assert editor(c, s, %{"budget" => "0"}).quantity == 0
    # A player's price override deliberately permits waiting for a better price.
    custom = editor(c, s, %{"limit" => "0", "quantity" => "2"})
    assert custom.quantity == 2 and custom.limit == "0"
    assert {_, {:error, :price_changed}} = trade(c, s, custom)
    company = Game.get(s, "companies", "aco")
    assert editor(c, State.put(s, "companies", "aco", %{company | "unpaid" => 1})).quantity == 0
    cat = put_in(c.cat, ["routes", "Jakarta|Singapore"], nil)

    assert editor(%{c | cat: cat, definitions: %{c.definitions | catalogue: cat}}, s).quantity ==
             0
  end

  test "visit budget limits and skip decisions use the execution funding rules", c do
    s = available(c.s, 1_000_000)

    spec = %{
      id: "vb",
      company_id: "aco",
      ship_id: "aco:1",
      stop_id: nil,
      port: "Jakarta",
      configured: 50_000,
      visit: 0
    }

    budgeted = TijaraTides.Domain.AutomationWorld.reserve_visit(s, spec, 50_000, false)
    offer = editor(c, budgeted)
    assert offer.quantity > 0 and offer.quantity < editor(c, s).quantity
    assert {_, :ok} = trade(c, budgeted, offer)
    assert {_, {:error, _}} = trade(c, budgeted, offer, %{quantity: offer.quantity + 1})
    fill(c, budgeted, offer)

    skipped =
      TijaraTides.Domain.AutomationWorld.reserve_visit(s, %{spec | configured: nil}, 0, true)

    assert editor(c, skipped).quantity == 0
  end

  test "only stock meeting the receiving hold's shelf-life requirement is suggested", c do
    {s, old} = CargoLots.create(c.s, "fruit", 2, 30_000)
    {s, fresh} = CargoLots.create(s, "fruit", 3, 120_000)
    market = Game.get(s, "markets", "Jakarta|fruit")

    s =
      State.put(s, "markets", "Jakarta|fruit", %{market | "stock" => 5, "batches" => [old, fresh]})
      |> available(100_000_000)

    offer = editor(c, s, %{"good" => "fruit", "freshness_minutes" => "1"})
    assert offer.quantity == 3
    assert {_, :ok} = trade(c, s, offer, %{min_remaining_ms: 60_000})

    assert {_, {:error, :insufficient_fresh_cargo}} =
             trade(c, s, offer, %{quantity: 4, min_remaining_ms: 60_000})

    fill(c, s, offer, %{"min_remaining_ms" => 60_000})
    assert editor(c, s, %{"good" => "fruit", "freshness_minutes" => "3"}).quantity == 0
    assert editor(c, s, %{"good" => "fruit", "freshness_minutes" => "invalid"}).quantity == 0
  end

  test "a next-port sale does not suggest cargo that expires during the known inbound journey",
       c do
    {s, lot} = CargoLots.create(c.s, "fruit", 5, 1)

    batch =
      lot
      |> Map.merge(%{"good" => "fruit", "unit_cost" => 100})
      |> TijaraTides.Domain.Ship.CargoRows.decode()
      |> TijaraTides.Domain.Ship.CargoRows.encode()

    s = State.put(s, "ships", "aco:1", %{ship(s) | "cargo" => [batch]})
    market = Game.get(s, "markets", "Jakarta|fruit")

    s =
      State.put(s, "markets", "Jakarta|fruit", %{
        market
        | "buyer" => true,
          "demand" => 20,
          "budget" => 1_000_000
      })

    assert editor(c, s, %{"side" => "sell", "good" => "fruit"}, false).quantity == 0
  end

  test "owned stock is suggested instead of a larger market purchase and preserves other ships' claims",
       c do
    s = warehouse(c, c.s, "owned", 10)

    {:ok, s, _} =
      TijaraTides.Domain.WarehouseWorld.reserve(
        s,
        account(s),
        %{
          "warehouse" => "owned",
          "ship" => "aco:2",
          "good" => "lumber",
          "kind" => "stock",
          "quantity" => 7
        },
        "other-stock",
        c.cat
      )

    offer = editor(c, s)
    assert offer.quantity == 3
    assert {_, :ok} = trade(c, s, offer)
    assert {_, {:error, :insufficient_cargo}} = trade(c, s, offer, %{quantity: 4})
    before_market = Game.get(s, "markets", "Jakarta|lumber")
    loaded = fill(c, s, offer)
    assert Game.get(loaded, "markets", "Jakarta|lumber") == before_market
    assert hd(Game.get(loaded, "warehouses", "owned")["cargo"])["quantity"] == 7
  end

  test "earmarked owned stock remains collectable with no market stock and purchases skipped",
       c do
    s = warehouse(c, c.s, "first", 10) |> then(&warehouse(c, &1, "earmarked", 2))

    {:ok, s, _} =
      TijaraTides.Domain.WarehouseWorld.reserve(
        s,
        account(s),
        %{
          "warehouse" => "earmarked",
          "ship" => "aco:1",
          "good" => "lumber",
          "kind" => "stock",
          "quantity" => 2
        },
        "own-stock",
        c.cat
      )

    market = Game.get(s, "markets", "Jakarta|lumber")
    s = State.put(s, "markets", "Jakarta|lumber", %{market | "stock" => 0})

    spec = %{
      id: "vb",
      company_id: "aco",
      ship_id: "aco:1",
      stop_id: nil,
      port: "Jakarta",
      configured: nil,
      visit: 0
    }

    s = TijaraTides.Domain.AutomationWorld.reserve_visit(s, spec, 0, true)
    offer = editor(c, s)
    assert offer.good == "lumber" and offer.quantity == 2
    loaded = fill(c, s, offer)
    assert Game.get(loaded, "warehouses", "earmarked")["cargo"] == []
    assert hd(Game.get(loaded, "warehouses", "first")["cargo"])["quantity"] == 10
    assert Enum.sum(for b <- ship(loaded)["cargo"], do: b["quantity"]) == 2
  end

  test "owned-stock suggestions obey handling, cash, capacity, caps and onward funding", c do
    s = warehouse(c, c.s, "owned", 10)
    assert editor(c, s).quantity == 10
    assert editor(c, available(s, 0)).quantity == 0
    full = s |> cargo("iron_ore", 500) |> available(100_000_000)
    assert editor(c, full).quantity == 0
    row = Game.get(s, "warehouses", "owned")

    assert editor(c, State.put(s, "warehouses", "owned", %{row | "protected_ms" => 1})).quantity ==
             0

    capped = editor(c, s, %{"budget" => "5"})
    assert capped.quantity == 2
    fill(c, s, capped)
    cat = put_in(c.cat, ["routes", "Jakarta|Singapore"], nil)

    assert editor(%{c | cat: cat, definitions: %{c.definitions | catalogue: cat}}, s).quantity ==
             0
  end

  test "a sale default is capped by funded demand and unloads completely", c do
    s = cargo(c.s, "lumber", 20)
    market = Game.get(s, "markets", "Jakarta|lumber")

    s =
      State.put(s, "markets", "Jakarta|lumber", %{
        market
        | "buyer" => true,
          "demand" => 100,
          "budget" => 1_000_000
      })

    bid = Markets.quote(s, c.cat, "Jakarta", "lumber")["bid"]

    s =
      State.put(s, "markets", "Jakarta|lumber", %{
        Game.get(s, "markets", "Jakarta|lumber")
        | "budget" => bid * 7
      })

    offer = editor(c, s, %{"side" => "sell"})
    assert offer.quantity == 7
    assert {_, :ok} = trade(c, s, offer)
    assert {_, {:error, :insufficient_demand}} = trade(c, s, offer, %{quantity: 8})
    loaded = fill(c, s, offer)
    assert ship(loaded)["status"] == "unloading"
    assert Enum.sum(for b <- ship(loaded)["cargo"], do: b["quantity"]) == 13
  end

  property "suggested purchases execute across cash, stock, occupied hold and purchase caps", c do
    check all(
            cash <- integer(0..2_000_000),
            stock <- integer(0..500),
            aboard <- integer(0..500),
            cap <- integer(0..20_000),
            max_runs: 50,
            max_shrinking_steps: 100
          ) do
      s = c.s |> cargo("iron_ore", max(1, aboard)) |> available(cash)
      market = Game.get(s, "markets", "Jakarta|lumber")
      s = State.put(s, "markets", "Jakarta|lumber", %{market | "stock" => stock})
      offer = editor(c, s, %{"budget" => to_string(cap)})

      if offer.quantity > 0 do
        assert {_, :ok} = trade(c, s, offer)
        fill(c, s, offer)
      end
    end
  end

  property "suggested sales settle across cargo, demand and buyer funding", c do
    check all(
            aboard <- integer(1..100),
            demand <- integer(0..100),
            paid <- integer(0..100),
            max_runs: 50,
            max_shrinking_steps: 100
          ) do
      s = cargo(c.s, "lumber", aboard)
      market = Game.get(s, "markets", "Jakarta|lumber")

      s =
        State.put(s, "markets", "Jakarta|lumber", %{market | "buyer" => true, "demand" => demand})

      bid = Markets.quote(s, c.cat, "Jakarta", "lumber")["bid"]

      s =
        State.put(s, "markets", "Jakarta|lumber", %{
          Game.get(s, "markets", "Jakarta|lumber")
          | "budget" => paid * bid
        })

      offer = editor(c, s, %{"side" => "sell"})
      assert offer.quantity == Enum.min([aboard, demand, paid])

      if offer.quantity > 0 do
        assert {_, :ok} = trade(c, s, offer)
        assert {_, {:error, _}} = trade(c, s, offer, %{quantity: offer.quantity + 1})
        fill(c, s, offer)
      end
    end
  end

  property "current-port buy defaults also settle across cargo types and resource boundaries",
           c do
    check all(
            good <- member_of(["lumber", "iron_ore", "copper_scrap"]),
            cash <- integer(0..2_000_000),
            stock <- integer(0..500),
            aboard <- integer(1..500),
            max_runs: 50,
            max_shrinking_steps: 100
          ) do
      s = c.s |> cargo("iron_ore", aboard) |> available(cash) |> at_visit()
      market = Game.get(s, "markets", "Jakarta|" <> good)
      s = State.put(s, "markets", "Jakarta|" <> good, %{market | "stock" => stock})

      v = %{
        public: Visibility.public(s, c.cat),
        private: Visibility.private(s, account(s)),
        markets: Markets.quotes(s, c.cat)
      }

      limits = GameQueries.trade_limits(v, ship(s), "Singapore", c.cat)
      defaults = GameQueries.trade_defaults(v, ship(s), "Singapore", limits)
      maximum = limits[{"buy", good}]
      quantity = defaults[{"buy", good}]
      assert quantity <= maximum

      if maximum > 0 do
        command = %Trade{
          side: "buy",
          ship_id: "aco:1",
          good: good,
          quantity: maximum,
          limit: v.markets["Jakarta|" <> good]["ask"],
          destination: "Singapore"
        }

        assert :ok =
                 TijaraTides.Domain.Services.TradeSettlement.validate(
                   s,
                   account(s),
                   command,
                   c.cat
                 )

        assert {:error, _} =
                 TijaraTides.Domain.Services.TradeSettlement.validate(
                   s,
                   account(s),
                   %{command | quantity: maximum + 1},
                   c.cat
                 )

        if quantity > 0 do
          assert {:ok, changed, reply} =
                   TijaraTides.Domain.Services.BerthAllocation.submit(
                     s,
                     account(s),
                     %{command | quantity: quantity},
                     c.cat
                   )

          refute reply["queued"]
          assert ship(changed)["status"] == "loading"

          assert Enum.sum(for b <- ship(changed)["cargo"], b["good"] == good, do: b["quantity"]) ==
                   Enum.sum(for b <- ship(s)["cargo"], b["good"] == good, do: b["quantity"]) +
                     quantity
        end
      else
        assert quantity == 0
      end
    end
  end

  property "unchanged suggested instructions progress through real travel and automatic departure",
           c do
    check all(cash <- integer(50_000..300_000), max_runs: 30, max_shrinking_steps: 100) do
      s = available(c.s, cash)
      offer = editor(c, s, %{}, false)
      assert offer.quantity > 0

      {:ok, s, _} =
        ShipWorld.add_instruction(
          s,
          account(s),
          %{
            "ship" => "aco:1",
            "port" => "Jakarta",
            "side" => "buy",
            "good" => "lumber",
            "quantity" => offer.quantity,
            "limit" => offer.limit |> Decimal.new() |> Decimal.mult(100) |> Decimal.to_integer(),
            "budget" => String.to_integer(offer.budget) * 100,
            "onward" => "Singapore"
          },
          %{id: "journey", catalogue: c.cat}
        )

      quote = Fleet.voyage_quote(ship(s), "Jakarta", c.cat, 0, 0)

      {:ok, s, _} =
        Game.execute(
          s,
          account(s),
          %{
            "action" => "sail",
            "ship" => "aco:1",
            "destination" => "Jakarta",
            "fuel_limit" => quote["fuel"]
          },
          %{},
          c.cat
        )

      loaded = Game.advance(s, ship(s)["arrive_ms"] - s.clock_ms, c.cat)
      assert Game.get(loaded, "ship_instructions", "journey")["filled"] == offer.quantity
      assert ship(loaded)["status"] == "loading"
      finished = Game.advance(loaded, ship(loaded)["arrive_ms"] - loaded.clock_ms, c.cat)
      assert ship(finished)["status"] == "sailing"
      assert ship(finished)["destination"] == "Singapore"
    end
  end
end
