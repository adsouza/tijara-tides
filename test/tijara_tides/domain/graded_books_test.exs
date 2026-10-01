defmodule TijaraTides.Domain.GradedBooksTest do
  use ExUnit.Case, async: true

  alias TijaraTides.Domain.{
    Game,
    State,
    Warehouse,
    WarehouseWorld,
    CargoLots,
    OrderBookWorld,
    OrderBook,
    CargoFreshness,
    CompanyFinanceWorld
  }

  alias TijaraTides.Domain.Ship.{CargoBatch, CargoRows}
  alias TijaraTides.Domain.Services.Exchange

  setup do
    cat =
      TijaraTides.Infrastructure.GameCatalogue.all()
      |> put_in(["goods", "fruit", "shelf_ms"], 1000)

    s = Game.initialize(%{entities: %{}, clock_ms: 0, epoch: 1, revision: 0}, cat)
    {:ok, s, _} = Game.seed_invite(s, "invite")
    {:ok, s, _} = Game.redeem(s, "invite", "session", %{id: "a", wall_ms: 0})
    a = State.get(s, "accounts", "a")
    s = State.put(s, "accounts", "b", %{a | "id" => "b"})

    s =
      Enum.reduce(["a", "b"], s, fn id, s ->
        {:ok, s, _} =
          TijaraTides.CompanyFixture.create_company(
            s,
            State.get(s, "accounts", id),
            id,
            "Jakarta",
            "general",
            %{id: id <> "co", catalogue: cat}
          )

        {:ok, s, _} =
          WarehouseWorld.lease(
            s,
            State.get(s, "accounts", id),
            %{
              "port" => "Jakarta",
              "storage" => "dry",
              "blocks" => 2,
              "days" => 1,
              "price" => Warehouse.quote(WarehouseWorld.used(s, "Jakarta", "dry"), "dry", 2, 1)
            },
            id <> "w",
            cat
          )

        s
      end)

    m = State.get(s, "markets", "Jakarta|fruit")

    s =
      State.put(s, "markets", "Jakarta|fruit", %{m | "stock" => 0, "batches" => [], "demand" => 0})

    %{
      state: s,
      catalogue: cat,
      a: State.get(s, "accounts", "a"),
      b: State.get(s, "accounts", "b")
    }
  end

  defp stock(c, s, groups) do
    {s, cargo} =
      Enum.reduce(groups, {s, []}, fn {n, life}, {s, cargo} ->
        {s, lot} = CargoLots.create(s, "fruit", n, life)

        b = %CargoBatch{
          good: "fruit",
          quantity: n,
          lot_id: lot["lot_id"],
          expires_ms: life,
          unit_cost: 10
        }

        b = CargoFreshness.initialize(b, s.clock_ms, c.catalogue["goods"]["fruit"])
        {s, cargo ++ [CargoRows.encode(b)]}
      end)

    w = State.get(s, "warehouses", "aw")

    s
    |> State.put("warehouses", "aw", %{w | "cargo" => cargo})
    |> CompanyFinanceWorld.post("aco", "purchase", [
      {"inventory", Enum.sum(for b <- cargo, do: b["quantity"] * 10)},
      {"cash_available", -Enum.sum(for b <- cargo, do: b["quantity"] * 10)}
    ])
  end

  defp order(c, s, who, side, qty, id, extra \\ %{}) do
    Exchange.place(
      %{s | revision: s.revision + 1},
      c[who],
      Map.merge(
        %{
          "warehouse" => Atom.to_string(who) <> "w",
          "good" => "fruit",
          "side" => side,
          "quantity" => qty,
          "price" => 1000
        },
        extra
      ),
      id,
      c.catalogue
    )
  end

  defp markdowns, do: %{"fresh" => 100, "good" => 80, "fair" => 50, "clearance" => 20}

  test "mixed-grade backing fills only eligible portions at their resting prices", c do
    s = stock(c, c.state, [{2, 900}, {2, 500}])
    {:ok, s, _} = order(c, s, :a, "sell", 4, "sell", %{"markdowns" => markdowns()})
    quotes = OrderBook.quotes(OrderBookWorld.fetch(s, "sell"))

    assert Enum.sort(Enum.map(quotes, &{&1.actual_grade, &1.price, &1.quantity})) == [
             {2, 800, 2},
             {3, 1000, 2}
           ]

    {:ok, s, _} = order(c, s, :b, "buy", 2, "fresh-buy", %{"min_grade" => 3})
    cargo = State.get(s, "warehouses", "bw")["cargo"]
    assert Enum.all?(cargo, &(&1["expires_ms"] == 900 and &1["unit_cost"] == 1000))
    assert OrderBookWorld.fetch(s, "sell").quantity == 2
    {:ok, s, _} = order(c, s, :b, "buy", 2, "old-buy")
    assert OrderBookWorld.fetch(s, "sell") == nil

    assert Enum.any?(
             State.get(s, "warehouses", "bw")["cargo"],
             &(&1["expires_ms"] == 500 and &1["unit_cost"] == 800)
           )
  end

  test "aging resets changed portions while unchanged and split portions retain priority", c do
    s = stock(c, c.state, [{2, 900}, {2, 500}])
    {:ok, s, _} = order(c, s, :a, "sell", 4, "sell", %{"markdowns" => markdowns()})
    s = Exchange.advance(%{s | clock_ms: 100, revision: 1}, c.catalogue)
    portions = OrderBook.quotes(OrderBookWorld.fetch(s, "sell"))
    assert Enum.any?(portions, &(&1.actual_grade == 3 and &1.priority_ms == 0))

    assert Enum.any?(
             portions,
             &(&1.actual_grade == 1 and &1.priority_ms == 100 and &1.price == 500)
           )

    {:ok, s, _} = order(c, s, :b, "buy", 1, "buy", %{"min_grade" => 3})

    fresh =
      OrderBook.quotes(OrderBookWorld.fetch(s, "sell")) |> Enum.find(&(&1.actual_grade == 3))

    assert fresh.quantity == 1
    assert fresh.priority_ms == 0
  end

  test "buyer minimum lifetime is checked under receiving conditions", c do
    s = stock(c, c.state, [{2, 500}])
    {:ok, s, _} = order(c, s, :a, "sell", 2, "sell")
    {:ok, s, _} = order(c, s, :b, "buy", 2, "buy", %{"min_remaining_ms" => 600})
    assert OrderBookWorld.fetch(s, "buy").quantity == 2
    w = State.get(s, "warehouses", "bw")

    s =
      State.put(s, "warehouses", "bw", %{w | "storage" => "reefer"})
      |> Exchange.advance(c.catalogue)

    assert OrderBookWorld.fetch(s, "buy") == nil
    assert hd(State.get(s, "warehouses", "bw")["cargo"])["expires_ms"] == 2000
  end

  test "complete schedules, copied basis, floors and eligibility amendments preserve atomicity",
       c do
    s = stock(c, c.state, [{2, 600}])

    assert {:error, :exchange_freshness_invalid} =
             order(c, s, :a, "sell", 2, "bad", %{"markdowns" => %{"good" => 80}})

    {:ok, s, _} =
      order(c, s, :a, "sell", 2, "sell", %{"markdowns" => markdowns(), "price_floor" => 900})

    assert hd(OrderBook.quotes(OrderBookWorld.fetch(s, "sell"))).price == 900
    s = %{s | clock_ms: 10, revision: 1}

    {:ok, s, _} =
      Exchange.amend(s, c.a, %{"order" => "sell", "quantity" => 1, "price" => 1000}, c.catalogue)

    assert hd(OrderBook.quotes(OrderBookWorld.fetch(s, "sell"))).priority_ms == 0

    {:ok, s, _} =
      Exchange.amend(
        s,
        c.a,
        %{"order" => "sell", "quantity" => 1, "price" => 2000, "rebase" => true},
        c.catalogue
      )

    assert hd(OrderBook.quotes(OrderBookWorld.fetch(s, "sell"))).price == 1600
    assert hd(OrderBook.quotes(OrderBookWorld.fetch(s, "sell"))).priority_ms == 10
  end

  test "spoilage cancels only expired backing and retains the other portion", c do
    s = stock(c, c.state, [{2, 900}, {2, 100}])
    {:ok, s, _} = order(c, s, :a, "sell", 4, "sell")

    s =
      %{s | clock_ms: 100} |> WarehouseWorld.advance(c.catalogue) |> Exchange.advance(c.catalogue)

    assert OrderBookWorld.fetch(s, "sell").quantity == 2
    assert Enum.sum(Enum.map(WarehouseWorld.fetch(s, "aw").reservations, & &1.quantity)) == 2

    assert Enum.sum(Enum.map(OrderBook.quotes(OrderBookWorld.fetch(s, "sell")), & &1.quantity)) ==
             2
  end

  test "preset names validate the persisted value in code points", c do
    alias TijaraTides.Domain.MarkdownPresetWorld, as: Presets

    for unit <- ["e\u0301", "👍🏽", "🚢", "a"] do
      width = length(String.codepoints(unit))
      name = String.duplicate(unit, div(80, width)) <> String.duplicate("x", rem(80, width))
      assert length(String.codepoints(name)) == 80

      {:ok, s, _} =
        Presets.save(
          c.state,
          c.a,
          %{"name" => "  " <> name <> "  ", "markdowns" => markdowns()},
          "unicode"
        )

      assert State.get(s, "markdown_presets", "unicode")["name"] == name

      assert {:error, :exchange_freshness_invalid} =
               Presets.save(
                 s,
                 c.a,
                 %{"preset" => "unicode", "name" => name <> "x", "markdowns" => markdowns()},
                 "unused"
               )

      assert State.get(s, "markdown_presets", "unicode")["name"] == name
    end

    for name <- [nil, 123, "", " \t\n "] do
      assert {:error, :exchange_freshness_invalid} =
               Presets.save(
                 c.state,
                 c.a,
                 %{"name" => name, "markdowns" => markdowns()},
                 "invalid"
               )
    end
  end

  test "preset names reject control and format characters on creation and amendment", c do
    alias TijaraTides.Domain.MarkdownPresetWorld, as: Presets
    payload = %{"name" => "Food", "markdowns" => markdowns()}
    {:ok, s, _} = Presets.save(c.state, c.a, payload, "owned")

    for name <- [
          "Food\u0000",
          "A\u0001B",
          "A\nB",
          "A\tB",
          "A\u007FB",
          "A\u0085B",
          "A\u200BB",
          "A\u202EB",
          "A\u2066B",
          "👩‍👩‍👧‍👦",
          <<255>>
        ],
        command <- [
          Map.put(payload, "name", name),
          Map.merge(payload, %{"name" => name, "preset" => "owned"})
        ] do
      assert {:error, :exchange_freshness_invalid} = Presets.save(s, c.a, command, "new")
    end

    assert State.get(s, "markdown_presets", "owned")["name"] == "Food"
    assert State.get(s, "markdown_presets", "new") == nil
  end

  test "supplied preset ids must identify an existing preset owned by the caller", c do
    alias TijaraTides.Domain.MarkdownPresetWorld, as: Presets
    payload = %{"name" => "Food", "markdowns" => markdowns()}
    {:ok, s, %{"preset" => "owned"}} = Presets.save(c.state, c.a, payload, "owned")

    for id <- [
          "missing",
          "",
          "id\u0000x",
          String.duplicate("x", 5000),
          nil,
          false,
          123,
          1.5,
          [],
          ["owned"],
          %{},
          %{"id" => "owned"}
        ] do
      assert {:error, :exchange_freshness_invalid} =
               Presets.save(s, c.a, Map.put(payload, "preset", id), "generated")
    end

    assert {:error, :exchange_freshness_invalid} =
             Presets.save(s, c.b, Map.put(payload, "preset", "owned"), "generated")

    {:ok, amended, %{"preset" => "owned"}} =
      Presets.save(
        s,
        c.a,
        Map.merge(payload, %{"preset" => "owned", "name" => "Updated"}),
        "generated"
      )

    assert State.get(amended, "markdown_presets", "owned")["name"] == "Updated"
    assert State.get(amended, "markdown_presets", "generated") == nil
  end

  test "preset ownership and applied copies survive edits and deletion", c do
    alias TijaraTides.Domain.MarkdownPresetWorld, as: Presets

    {:ok, s, _} =
      Presets.save(
        c.state,
        c.a,
        %{"name" => "Food", "markdowns" => markdowns(), "price_floor" => 900},
        "preset"
      )

    assert {:error, :exchange_freshness_invalid} = Presets.delete(s, c.b, "preset")
    assert Presets.apply(s, c.b, %{"preset" => "preset"})["markdowns"] == false

    {:ok, s, _} =
      order(c, stock(c, s, [{2, 600}]), :a, "sell", 2, "sell", %{"preset" => "preset"})

    original = OrderBookWorld.fetch(s, "sell")

    {:ok, s, _} =
      Presets.save(
        s,
        c.a,
        %{
          "preset" => "preset",
          "name" => "Changed",
          "markdowns" => Map.new(markdowns(), fn {k, _} -> {k, 10} end)
        },
        "unused"
      )

    assert OrderBookWorld.fetch(s, "sell") == original
    {:ok, s, _} = Presets.delete(s, c.a, "preset")
    assert OrderBookWorld.fetch(s, "sell") == original

    assert {:error, :exchange_freshness_invalid} =
             Presets.save(s, c.a, %{"name" => "Bad", "markdowns" => %{"fresh" => 100}}, "bad")
  end

  test "automated sales copy a preset and release only cargo meeting its grade minimum", c do
    alias TijaraTides.Domain.{ShipWorld, MarkdownPresetWorld, PortCargoMarketWorld}
    alias TijaraTides.Domain.Services.AutomatedVisits
    s = stock(c, c.state, [{2, 900}, {2, 500}])
    ship = State.owned(s, "ships", "company_id", "aco") |> hd()
    w = State.get(s, "warehouses", "aw")

    s =
      State.put(s, "warehouses", "aw", %{w | "cargo" => []})
      |> State.put("ships", ship["id"], %{ship | "cargo" => w["cargo"]})

    schedule = %{"fresh" => 100, "good" => 50, "fair" => 25, "clearance" => 10}

    {:ok, s, _} =
      MarkdownPresetWorld.save(s, c.a, %{"name" => "Food", "markdowns" => schedule}, "preset")

    q = PortCargoMarketWorld.quote(s, c.catalogue, "Singapore", "fruit")

    {:ok, s, _} =
      ShipWorld.add_instruction(
        s,
        c.a,
        %{
          "ship" => ship["id"],
          "port" => "Singapore",
          "good" => "fruit",
          "side" => "sell",
          "quantity" => 4,
          "limit" => q["bid"] + 1,
          "preset" => "preset"
        },
        %{id: "auto", catalogue: c.catalogue}
      )

    {:ok, s, _} = MarkdownPresetWorld.delete(s, c.a, "preset")
    ship = State.get(s, "ships", ship["id"])

    s =
      State.put(s, "ships", ship["id"], %{ship | "port" => "Singapore"})
      |> AutomatedVisits.advance(c.catalogue)

    assert State.get(s, "ship_instructions", "auto")["filled"] == 2
    assert State.get(s, "ship_instructions", "auto")["markdowns"] == schedule
    assert Enum.all?(State.get(s, "ships", ship["id"])["cargo"], &(&1["expires_ms"] == 900))
  end
end
