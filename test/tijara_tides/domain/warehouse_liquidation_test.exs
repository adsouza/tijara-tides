defmodule TijaraTides.Domain.WarehouseLiquidationTest do
  use ExUnit.Case, async: true

  alias TijaraTides.Domain.{
    Game,
    State,
    Warehouse,
    WarehouseWorld,
    CargoLots,
    CompanyFinanceWorld,
    AuctionWorld,
    OrderBookWorld,
    Visibility
  }

  alias TijaraTides.Domain.Services.{WarehouseLiquidation, Exchange, Auctions, Estates}
  @day 86_400_000
  @grace @day + 43_200_000

  setup do
    cat =
      TijaraTides.Infrastructure.GameCatalogue.all()
      |> Map.put("auctions", %{"interval_ms" => 10_000, "window_ms" => 10_000})

    s = Game.initialize(%{entities: %{}, clock_ms: 0, epoch: 1, revision: 0}, cat)
    {:ok, s, _} = Game.seed_invite(s, "invite")
    {:ok, s, _} = Game.redeem(s, "invite", "session", %{id: "a", wall_ms: 0})
    a = State.get(s, "accounts", "a")

    s =
      Enum.reduce(["a", "b", "c"], s, fn id, s ->
        s = State.put(s, "accounts", id, %{a | "id" => id})

        {:ok, s, _} =
          TijaraTides.CompanyFixture.create_company(
            s,
            State.get(s, "accounts", id),
            id,
            "Jakarta",
            "general",
            %{id: id <> "co", catalogue: cat}
          )

        s
      end)

    s =
      Enum.reduce(["lumber", "fruit", "whisky"], s, fn good, s ->
        m = State.get(s, "markets", "Jakarta|" <> good)
        State.put(s, "markets", "Jakarta|" <> good, %{m | "stock" => 0, "demand" => 0})
      end)

    %{state: s, catalogue: cat}
  end

  defp lease(c, s, id, owner \\ "a", blocks \\ 10, storage \\ "dry", days \\ 1) do
    {:ok, s, _} =
      WarehouseWorld.lease(
        s,
        State.get(s, "accounts", owner),
        %{
          "port" => "Jakarta",
          "storage" => storage,
          "blocks" => blocks,
          "days" => days,
          "price" =>
            Warehouse.quote(WarehouseWorld.used(s, "Jakarta", storage), storage, blocks, days)
        },
        id,
        c.catalogue
      )

    s
  end

  defp stock(s, id, goods) do
    w = State.get(s, "warehouses", id)

    {batches, s} =
      Enum.map_reduce(goods, s, fn {good, n, expiry, cost}, s ->
        {s, lot} = CargoLots.create(s, good, n, expiry)
        {Map.merge(lot, %{"good" => good, "unit_cost" => cost}), s}
      end)

    s
    |> State.put("warehouses", id, %{w | "cargo" => w["cargo"] ++ batches})
    |> CompanyFinanceWorld.post(w["company_id"], "purchase", [
      {"inventory", Enum.sum(for b <- batches, do: b["quantity"] * b["unit_cost"])},
      {"cash_available", -Enum.sum(for b <- batches, do: b["quantity"] * b["unit_cost"])}
    ])
  end

  defp order(c, s, owner, warehouse, side, n, price, id, extra \\ %{}) do
    {:ok, s, _} =
      Exchange.place(
        s,
        State.get(s, "accounts", owner),
        Map.merge(
          %{
            "warehouse" => warehouse,
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

    s
  end

  defp advance(c, s, clock), do: WarehouseWorld.advance(%{s | clock_ms: clock}, c.catalogue)

  defp auctions(s, warehouse),
    do: Enum.filter(AuctionWorld.all(s), &(&1.liquidation_id == warehouse))

  defp close(c, s, clock),
    do:
      Auctions.reconcile(%{s | clock_ms: clock}, c.catalogue)
      |> WarehouseWorld.advance(c.catalogue)

  test "buy orders fill in price/time priority before auctions and receiving cargo survives the same tick",
       c do
    s =
      lease(c, c.state, "a-store")
      |> then(&lease(c, &1, "z-buyer", "b", 10, "dry", 3))
      |> then(&lease(c, &1, "z-third", "c", 10, "dry", 3))

    s = stock(s, "a-store", [{"lumber", 80, nil, 100}])
    s = order(c, s, "a", "a-store", "sell", 80, 999_999, "owner-minimum")
    s = order(c, s, "b", "z-buyer", "buy", 20, 1000, "first")
    s = order(c, %{s | revision: 1}, "c", "z-third", "buy", 15, 1200, "best")
    s = advance(c, s, @grace)
    p = WarehouseLiquidation.pool(s, "a-store")
    assert p["proceeds"] == 20_000 + 18_000
    assert p["status"] == "liquidating"
    assert State.get(s, "companies", "aco")["reserved"] == p["proceeds"]
    assert State.get(s, "warehouses", "a-store")["blocks"] == 1

    assert Enum.sum(for b <- State.get(s, "warehouses", "z-buyer")["cargo"], do: b["quantity"]) ==
             20

    assert Enum.sum(for b <- State.get(s, "warehouses", "z-third")["cargo"], do: b["quantity"]) ==
             15

    assert OrderBookWorld.fetch(s, "owner-minimum") == nil
    assert OrderBookWorld.fetch(s, "best") == nil
    assert OrderBookWorld.fetch(s, "first") == nil
    [a] = auctions(s, "a-store")
    assert a.quantity == 45
    assert a.opens_ms > @grace
    assert a.closes_ms - a.opens_ms == 10_000
    assert WarehouseWorld.used(s, "Jakarta", "dry") == 21
    s = close(c, s, a.closes_ms)
    p = WarehouseLiquidation.pool(s, "a-store")
    assert p["status"] == "completed"
    assert p["proceeds"] == 38_000 + 45 * 2500
    assert p["charged"] + p["paid"] == p["proceeds"]
    assert State.get(s, "companies", "aco")["reserved"] == 0
    assert State.get(s, "warehouses", "a-store") == nil
    assert close(c, s, a.closes_ms) == s
  end

  test "lease pools cannot subsidize each other or draw other cash for a shortfall", c do
    s = lease(c, c.state, "a-empty", "a", 1) |> then(&lease(c, &1, "b-rich", "a", 1))

    s =
      stock(s, "a-empty", [{"lumber", 1, nil, 100}]) |> stock("b-rich", [{"lumber", 2, nil, 100}])

    # One pool waits long enough that its charges exhaust its small proceeds.
    s = advance(c, s, @grace)
    first = hd(auctions(s, "a-empty"))
    second = hd(auctions(s, "b-rich"))
    cash = State.get(s, "companies", "aco")["cash"]
    s = close(c, s, second.closes_ms)
    rich = WarehouseLiquidation.pool(s, "b-rich")
    assert rich["paid"] > 0
    assert rich["proceeds"] == 5000
    # A second scenario makes the shortfall independent of the already-paid pool.
    s =
      lease(c, %{s | clock_ms: second.closes_ms}, "short", "a", 1)
      |> stock("short", [{"lumber", 1, nil, 100}])

    expiry = State.get(s, "warehouses", "short")["expires_ms"]
    s = advance(c, s, expiry + 43_200_000)
    a = hd(auctions(s, "short"))
    before = State.get(s, "companies", "aco")["cash"]
    s = close(c, s, a.closes_ms + 100 * @day)
    short = WarehouseLiquidation.pool(s, "short")
    assert short["charged"] == short["proceeds"]
    assert short["paid"] == 0

    assert State.get(s, "companies", "aco")["cash"] ==
             before - short["proceeds"] + short["proceeds"]

    assert State.get(s, "companies", "aco")["unpaid"] == 0
    assert State.get(s, "companies", "aco")["bankruptcy_ms"] == nil
    assert WarehouseLiquidation.pool(s, "b-rich") == rich
    assert first.closes_ms == second.closes_ms
    assert before > cash
  end

  test "rent accrual is invariant to tick partition and charges only still occupied blocks", c do
    s = lease(c, c.state, "store", "a", 10) |> stock("store", [{"lumber", 80, nil, 100}])
    one = advance(c, s, @grace + 7000)

    many =
      Enum.reduce([@day, @day + 1, @grace - 1, @grace, @grace + 7000], s, &advance(c, &2, &1))

    p = WarehouseLiquidation.pool(one, "store")
    q = WarehouseLiquidation.pool(many, "store")
    assert p["rent_due"] == q["rent_due"]
    assert p["rent_remainder"] == q["rent_remainder"]
    assert p["occupied_blocks"] == 2
    [a] = auctions(many, "store")
    at_boundary = WarehouseLiquidation.pool(advance(c, s, @grace), "store")
    expected_numerator = 7000 * p["rent"] * 2 * 12_500 + at_boundary["rent_remainder"]
    denominator = p["duration_ms"] * p["original_blocks"] * 10_000
    assert p["rent_due"] == at_boundary["rent_due"] + div(expected_numerator, denominator)
    assert a.closes_ms - a.opens_ms == 10_000
  end

  test "expiry cancels receiving orders with refund but permits sales during the snapshotted grace",
       c do
    c = %{
      c
      | catalogue:
          Map.put(c.catalogue, "warehouse_liquidation", %{
            "grace_ms" => 6000,
            "surcharge_bps" => 4000
          })
    }

    s = lease(c, c.state, "store") |> stock("store", [{"lumber", 2, nil, 100}])
    s = order(c, s, "a", "store", "buy", 1, 1, "incoming")
    s = advance(c, s, @day)
    assert OrderBookWorld.fetch(s, "incoming") == nil
    assert State.get(s, "companies", "aco")["reserved"] == 0
    s = order(c, s, "a", "store", "sell", 2, 999_999, "grace-sale")

    changed = %{
      c
      | catalogue:
          Map.put(c.catalogue, "warehouse_liquidation", %{"grace_ms" => 1, "surcharge_bps" => 0})
    }

    s = advance(changed, s, @day + 5999)
    assert OrderBookWorld.fetch(s, "grace-sale") != nil
    assert WarehouseLiquidation.pool(s, "store")["grace_end_ms"] == @day + 6000
    assert WarehouseLiquidation.pool(s, "store")["surcharge_bps"] == 4000
    s = advance(changed, s, @day + 6000)
    assert OrderBookWorld.fetch(s, "grace-sale") == nil
    assert hd(auctions(s, "store")).quantity == 2

    assert {:error, :auction_locked} =
             Auctions.withdraw_lot(s, State.get(s, "accounts", "a"), hd(auctions(s, "store")).id)
  end

  test "perishables clear endangered FEFO batches, auction surviving batches for a full window, and project freshness",
       c do
    s =
      lease(c, c.state, "cold", "a", 2, "reefer")
      |> stock("cold", [
        {"fruit", 2, @grace + 3_600_000, 100},
        {"fruit", 3, @grace + 15_000_000, 100}
      ])

    s = advance(c, s, @grace)
    p = WarehouseLiquidation.pool(s, "cold")
    assert p["proceeds"] == div(2 * 50_000 * 1000 * 3_600_000, 10_000 * 25_920_000)
    [a] = auctions(s, "cold")
    assert a.quantity == 3
    assert a.closes_ms - a.opens_ms == 7_200_000
    assert a.expires_ms == @grace + 15_000_000
    public = Enum.find(AuctionWorld.public(s), &(&1["id"] == a.id))
    assert public["expires_ms"] > public["closes_ms"]
    assert public["liquidation"]
    refute Map.has_key?(public, "liquidation_id")
    remaining = hd(State.get(s, "warehouses", "cold")["cargo"])
    assert remaining["expires_ms"] == a.expires_ms
    s = close(c, s, a.closes_ms)
    q = WarehouseLiquidation.pool(s, "cold")

    assert q["proceeds"] ==
             div(
               (2 * 3_600_000 + 3 * (a.expires_ms - a.closes_ms)) * 50_000 * 1000,
               10_000 * 25_920_000
             )

    assert q["status"] == "completed"
    assert State.get(s, "warehouses", "cold") == nil
  end

  test "spoiled perishables are discarded without proceeds and handling protection completes first",
       c do
    s = lease(c, c.state, "cold", "a", 1, "reefer") |> stock("cold", [{"fruit", 2, @grace, 100}])
    w = State.get(s, "warehouses", "cold")
    s = State.put(s, "warehouses", "cold", %{w | "protected_ms" => @grace + 5000})
    s = advance(c, s, @grace)
    assert State.get(s, "warehouses", "cold")["cargo"] == []
    assert auctions(s, "cold") == []
    assert WarehouseLiquidation.pool(s, "cold")["proceeds"] == 0
    s = advance(c, s, @grace + 5000)
    assert State.get(s, "warehouses", "cold") == nil
    assert WarehouseLiquidation.pool(s, "cold")["charged"] == 0
    assert State.get(s, "companies", "aco")["unpaid"] == 0
  end

  test "bankruptcy during liquidation retains auctions and sinks outstanding net proceeds once",
       c do
    s =
      lease(c, c.state, "store")
      |> then(&lease(c, &1, "buyer", "b", 10, "dry", 3))
      |> stock("store", [{"lumber", 3, nil, 100}])

    s = advance(c, s, @grace)
    [a] = auctions(s, "store")
    s = %{s | clock_ms: a.opens_ms}

    {:ok, s, _} =
      Auctions.bid(
        s,
        State.get(s, "accounts", "b"),
        %{"auction" => a.id, "warehouse" => "buyer", "price" => a.reserve + 1000},
        "bid",
        c.catalogue
      )

    {:ok, s, _} =
      TijaraTides.Domain.Services.Bankruptcy.bankrupt(s, State.get(s, "accounts", "a"), "forced")

    s = Estates.advance(s, c.catalogue)
    assert AuctionWorld.fetch(s, a.id) == a |> Map.put(:bids, AuctionWorld.fetch(s, a.id).bids)
    assert State.get(s, "warehouses", "store")["expires_ms"] == @day
    s = close(c, s, a.closes_ms)
    p = WarehouseLiquidation.pool(s, "store")
    assert p["status"] == "completed"
    assert p["paid"] == 0
    assert p["sunk"] == p["proceeds"] - p["charged"]
    assert p["sunk"] > 0

    assert Enum.sum(
             for b <- State.get(s, "warehouses", "award:" <> a.id)["cargo"], do: b["quantity"]
           ) == 3

    assert State.get(s, "companies", "aco")["reserved"] == 0
    assert State.get(s, "companies", "bco")["reserved"] == 0
    assert close(c, s, a.closes_ms) == s
    assert Visibility.private(s, State.get(s, "accounts", "b"))["warehouse_liquidations"] == %{}
  end

  test "invalid or expired receiving orders are skipped and forced sale ignores owner price", c do
    s =
      lease(c, c.state, "store")
      |> then(&lease(c, &1, "buyer", "b", 10, "dry", 3))
      |> stock("store", [{"lumber", 2, nil, 100}])

    s = order(c, s, "b", "buyer", "buy", 1, 9999, "expired", %{"expires_ms" => @grace})
    s = order(c, s, "b", "buyer", "buy", 1, 9000, "blocked")
    s = State.delete(s, "warehouse_reservations", "exchange:blocked")
    s = advance(c, s, @grace)
    assert WarehouseLiquidation.pool(s, "store")["proceeds"] == 0
    assert hd(auctions(s, "store")).quantity == 2
  end

  test "clearance batch splitting preserves aggregate proceeds and charge cap", c do
    s =
      lease(c, c.state, "cold", "a", 2, "reefer")
      |> stock("cold", [{"fruit", 3, @grace + 12_345, 100}])

    whole = advance(c, s, @grace)
    w = State.get(s, "warehouses", "cold")
    [batch] = w["cargo"]
    {s, child} = CargoLots.create(s, "fruit", 1, batch["expires_ms"], batch["lot_id"])
    {s, rest} = CargoLots.create(s, "fruit", 2, batch["expires_ms"], batch["lot_id"])

    s =
      State.put(s, "warehouses", "cold", %{
        w
        | "cargo" => [
            Map.merge(child, %{"good" => "fruit", "unit_cost" => 100}),
            Map.merge(rest, %{"good" => "fruit", "unit_cost" => 100})
          ]
      })

    split = advance(c, s, @grace)

    assert WarehouseLiquidation.pool(whole, "cold")["proceeds"] ==
             WarehouseLiquidation.pool(split, "cold")["proceeds"]

    assert WarehouseLiquidation.pool(whole, "cold")["charged"] ==
             WarehouseLiquidation.pool(split, "cold")["charged"]

    assert WarehouseLiquidation.pool(whole, "cold")["paid"] ==
             WarehouseLiquidation.pool(split, "cold")["paid"]
  end

  test "unsold lots clear their own batches while another lot settles to its buyer", c do
    s =
      lease(c, c.state, "cold", "a", 176, "reefer")
      |> then(&lease(c, &1, "receiving", "b", 16, "reefer", 3))
      |> stock("cold", [
        {"fruit", 10_000, @grace + 12_000_000, 1},
        {"fruit", 1000, @grace + 20_000_000, 7}
      ])

    s = advance(c, s, @grace)
    [first, second] = Enum.sort_by(auctions(s, "cold"), & &1.id)
    assert first.quantity == 10_000
    assert second.quantity == 1000
    s = %{s | clock_ms: second.opens_ms}

    {:ok, s, _} =
      Auctions.bid(
        s,
        State.get(s, "accounts", "b"),
        %{"auction" => second.id, "warehouse" => "receiving", "price" => second.reserve},
        "fresh-bid",
        c.catalogue
      )

    s = close(c, s, second.closes_ms)
    assert AuctionWorld.fetch(s, first.id).status == "unsold"
    assert AuctionWorld.fetch(s, second.id).status == "sold"
    [cargo] = State.get(s, "warehouses", "award:" <> second.id)["cargo"]
    assert cargo["expires_ms"] == @grace + 20_000_000
    assert cargo["quantity"] == 1000
    assert WarehouseLiquidation.pool(s, "cold")["status"] == "completed"
  end

  test "a late close does not replace a promised fresh lot with leftovers from a cancelled lot",
       c do
    s =
      lease(c, c.state, "cold", "a", 176, "reefer")
      |> then(&lease(c, &1, "receiving", "b", 16, "reefer", 3))
      |> stock("cold", [
        {"fruit", 5000, @grace + 12_000_000, 1},
        {"fruit", 5000, @grace + 15_000_000, 2},
        {"fruit", 1000, @grace + 20_000_000, 7}
      ])

    s = advance(c, s, @grace)
    [first, second] = Enum.sort_by(auctions(s, "cold"), & &1.id)
    s = %{s | clock_ms: second.opens_ms}

    {:ok, s, _} =
      Auctions.bid(
        s,
        State.get(s, "accounts", "b"),
        %{"auction" => second.id, "warehouse" => "receiving", "price" => second.reserve},
        "late-bid",
        c.catalogue
      )

    s = close(c, s, @grace + 14_000_000)
    assert AuctionWorld.fetch(s, first.id).status == "cancelled"
    assert AuctionWorld.fetch(s, second.id).status == "sold"
    [cargo] = State.get(s, "warehouses", "award:" <> second.id)["cargo"]
    assert cargo["expires_ms"] == @grace + 20_000_000
    assert cargo["quantity"] == 1000
    assert WarehouseLiquidation.pool(s, "cold")["status"] == "completed"
    assert State.get(s, "warehouses", "cold") == nil
  end
end
