defmodule TijaraTides.Domain.ExchangeTest do
  alias TijaraTides.Domain.OrderBookWorld
  use ExUnit.Case, async: true
  alias TijaraTides.Domain.{Game, State, Warehouse, OrderBook, CargoLots, CompanyFinance}
  alias TijaraTides.Domain.Services.Exchange

  setup do
    catalogue = TijaraTides.Infrastructure.GameCatalogue.all()
    state = Game.initialize(%{entities: %{}, clock_ms: 0, epoch: 1, revision: 0}, catalogue)
    {:ok, state, _} = Game.seed_invite(state, "invite")
    {:ok, state, _} = Game.redeem(state, "invite", "session", %{id: "a", wall_ms: 0})
    a = Game.get(state, "accounts", "a")
    state = State.put(state, "accounts", "b", %{a | "id" => "b"})

    state =
      Enum.reduce(["a", "b"], state, fn id, s ->
        {:ok, s, _} =
          TijaraTides.CompanyFixture.create_company(
            s,
            Game.get(s, "accounts", id),
            id,
            "Jakarta",
            "general",
            %{id: id <> "co", catalogue: catalogue}
          )

        account = Game.get(s, "accounts", id)

        {:ok, s, _} =
          Warehouse.lease(
            s,
            account,
            %{
              "port" => "Jakarta",
              "storage" => "dry",
              "blocks" => 10,
              "days" => 1,
              "price" => Warehouse.quote(Warehouse.used(s, "Jakarta", "dry"), "dry", 10, 1)
            },
            id <> "w",
            catalogue
          )

        s
      end)

    # Isolate the player order book from NPC liquidity unless a test opts in.
    market = Game.get(state, "markets", "Jakarta|lumber")
    state = State.put(state, "markets", "Jakarta|lumber", %{market | "stock" => 0, "demand" => 0})

    %{
      state: state,
      catalogue: catalogue,
      a: Game.get(state, "accounts", "a"),
      b: Game.get(state, "accounts", "b")
    }
  end

  defp stock(c, state, owner, n) do
    {state, lot} = CargoLots.create(state, "lumber", n, nil)
    row = Game.get(state, "warehouses", owner <> "w")

    state =
      State.put(state, "warehouses", row["id"], %{
        row
        | "cargo" => row["cargo"] ++ [Map.merge(lot, %{"good" => "lumber", "unit_cost" => 100})]
      })

    CompanyFinance.post(state, c[String.to_existing_atom(owner)]["company_id"], "purchase", [
      {"inventory", n * 100},
      {"cash_available", -n * 100}
    ])
  end

  defp order(c, state, owner, side, n, price, id, extra \\ %{}) do
    Exchange.place(
      state,
      c[String.to_existing_atom(owner)],
      Map.merge(
        %{
          "warehouse" => owner <> "w",
          "good" => "lumber",
          "side" => side,
          "quantity" => n,
          "price" => price
        },
        extra
      ),
      id,
      c.catalogue
    )
  end

  test "price-time partial fills settle at resting prices and release price improvement", c do
    s = stock(c, c.state, "a", 10)
    {:ok, s, _} = order(c, s, "a", "sell", 3, 900, "first")
    {:ok, s, _} = order(c, %{s | revision: 1}, "a", "sell", 4, 800, "best")
    {:ok, s, _} = order(c, %{s | revision: 2}, "a", "sell", 3, 900, "later")
    cash = Game.get(s, "companies", "bco")["cash"]
    {:ok, s, _} = order(c, %{s | revision: 3}, "b", "buy", 8, 1000, "buy")
    assert OrderBookWorld.fetch(s, "first") == nil
    assert OrderBookWorld.fetch(s, "best") == nil
    assert OrderBookWorld.fetch(s, "later").quantity == 2
    assert OrderBookWorld.fetch(s, "buy") == nil
    assert Game.get(s, "companies", "bco")["cash"] == cash - 4 * 800 - 4 * 900
    assert Game.get(s, "companies", "bco")["reserved"] == 0
    assert Enum.sum(for b <- Game.get(s, "warehouses", "bw")["cargo"], do: b["quantity"]) == 8
  end

  test "reductions retain priority, repricing resets it and failed amendments are atomic", c do
    {:ok, s, _} = order(c, c.state, "b", "buy", 10, 100, "buy")
    old = OrderBookWorld.fetch(s, "buy")

    {:ok, reduced, _} =
      Exchange.amend(
        %{s | revision: 4},
        c.b,
        %{"order" => "buy", "quantity" => 5, "price" => 100},
        c.catalogue
      )

    assert OrderBook.priority(OrderBookWorld.fetch(reduced, "buy")) == OrderBook.priority(old)
    assert Game.get(reduced, "companies", "bco")["reserved"] == 500

    {:ok, changed, _} =
      Exchange.amend(
        %{reduced | revision: 5},
        c.b,
        %{"order" => "buy", "quantity" => 5, "price" => 200},
        c.catalogue
      )

    assert OrderBookWorld.fetch(changed, "buy").priority_seq == 5

    assert {:error, :insufficient_cash} =
             Exchange.amend(
               changed,
               c.b,
               %{"order" => "buy", "quantity" => 10000, "price" => 1_000_000_000},
               c.catalogue
             )

    assert OrderBookWorld.fetch(changed, "buy").price == 200
    assert {:error, :exchange_invalid} = Exchange.cancel(changed, c.a, "buy")
    {:ok, cancelled, _} = Exchange.cancel(changed, c.b, "buy")
    assert Game.get(cancelled, "companies", "bco")["reserved"] == 0
    assert Game.get(cancelled, "warehouse_reservations", "exchange:buy") == nil
  end

  test "self trades are excluded and reserved stock cannot be collected", c do
    s = stock(c, c.state, "a", 10)
    {:ok, s, _} = order(c, s, "a", "sell", 10, 100, "sell")
    {:ok, s, _} = order(c, s, "a", "buy", 10, 100, "buy")
    assert OrderBookWorld.fetch(s, "sell").quantity == 10

    assert {:error, :insufficient_cargo} =
             Warehouse.transfer(
               s,
               c.a,
               %{
                 "warehouse" => "aw",
                 "ship" => "aco:1",
                 "good" => "lumber",
                 "quantity" => 1,
                 "side" => "collect"
               },
               c.catalogue
             )
  end

  test "expiry and lost backing release escrow; nonstandard cargo is rejected", c do
    {:ok, s, _} = order(c, c.state, "b", "buy", 10, 100, "buy", %{"expires_ms" => 1000})
    s = Exchange.reconcile(%{s | clock_ms: 1000})
    assert OrderBookWorld.fetch(s, "buy") == nil
    assert Game.get(s, "companies", "bco")["reserved"] == 0
    {:ok, s, _} = order(c, s, "b", "buy", 10, 100, "next")

    s =
      Warehouse.release_trade(s, OrderBook.claim(OrderBookWorld.fetch(s, "next")))
      |> Exchange.reconcile()

    assert OrderBookWorld.fetch(s, "next") == nil
    assert Game.get(s, "companies", "bco")["reserved"] == 0

    assert {:error, :exchange_invalid} =
             order(c, s, "a", "buy", 1, 100, "bad", %{"good" => "fruit"})
  end

  test "ticks share a fill budget and rotate past unfinished orders", c do
    {:ok, s, _} = order(c, c.state, "b", "buy", 30, 100_000, "first")
    {:ok, s, _} = order(c, %{s | revision: 1}, "b", "buy", 30, 100_000, "second")
    market = Game.get(s, "markets", "Jakarta|lumber")
    s = State.put(s, "markets", "Jakarta|lumber", %{market | "stock" => 500})

    s = Exchange.advance(s, c.catalogue, fills: 1)
    assert OrderBookWorld.fetch(s, "first").quantity == 5
    assert OrderBookWorld.fetch(s, "second").quantity == 30
    assert Game.get(s, "markets", "Jakarta|lumber")["stock"] == 475

    s = Exchange.advance(s, c.catalogue, fills: 1)
    assert OrderBookWorld.fetch(s, "first").quantity == 5
    assert OrderBookWorld.fetch(s, "second").quantity == 5

    # One fill finishes the first order; only one remains for the second order.
    s = Exchange.advance(s, c.catalogue, fills: 2)
    assert OrderBookWorld.orders(s) == []
    assert Game.get(s, "markets", "Jakarta|lumber")["stock"] == 440
    assert Exchange.advance(s, c.catalogue)[:exchange_cursor] == nil
  end

  test "non-executable visits are bounded and a removed cursor still resumes", c do
    {:ok, s, _} = order(c, c.state, "b", "buy", 1, 1, "blocked")
    {:ok, s, _} = order(c, %{s | revision: 1}, "b", "buy", 1, 100_000, "ready")
    market = Game.get(s, "markets", "Jakarta|lumber")
    s = State.put(s, "markets", "Jakarta|lumber", %{market | "stock" => 500})
    s = Exchange.advance(s, c.catalogue, orders: 1)
    assert OrderBookWorld.fetch(s, "ready").quantity == 1
    {:ok, s, _} = Exchange.cancel(s, c.b, "blocked")
    s = Exchange.advance(s, c.catalogue, orders: 1)
    assert OrderBookWorld.fetch(s, "ready") == nil
  end

  test "NPC fills obey changing depth and share finite market stock", c do
    m = Game.get(c.state, "markets", "Jakarta|lumber")
    s = State.put(c.state, "markets", "Jakarta|lumber", %{m | "stock" => 500})
    price = TijaraTides.Domain.PortCargoMarket.quote(s, c.catalogue, "Jakarta", "lumber")["ask"]
    {:ok, s, _} = order(c, s, "b", "buy", 30, price, "npc")
    assert OrderBookWorld.fetch(s, "npc").quantity == 5
    assert Game.get(s, "markets", "Jakarta|lumber")["stock"] == 475
    assert Game.get(s, "companies", "bco")["reserved"] == 5 * price
  end

  test "an incoming sell receives the resting bid and expired leases release cash", c do
    s = stock(c, c.state, "a", 4)
    {:ok, s, _} = order(c, s, "b", "buy", 4, 1200, "bid")
    {:ok, s, _} = order(c, %{s | revision: 1}, "a", "sell", 2, 800, "ask")
    assert Enum.all?(Game.get(s, "warehouses", "bw")["cargo"], &(&1["unit_cost"] == 1200))
    assert OrderBookWorld.fetch(s, "bid").quantity == 2
    s = Exchange.reconcile(%{s | clock_ms: 86_400_000})
    assert Game.get(s, "companies", "bco")["reserved"] == 0
    assert OrderBookWorld.fetch(s, "bid") == nil
  end

  test "cancellable buy escrow does not make a solvent company eligible for bankruptcy", c do
    {:ok, s, _} = TijaraTides.Domain.Services.Credit.borrow(c.state, c.b, 1_000_000, "loan")
    company = Game.get(s, "companies", "bco")
    {:ok, s, _} = order(c, s, "b", "buy", 1, company["cash"], "escrow")
    refute CompanyFinance.can_declare_bankruptcy?(s, c.b)
  end
end
