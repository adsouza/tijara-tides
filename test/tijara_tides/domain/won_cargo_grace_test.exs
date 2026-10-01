defmodule TijaraTides.Domain.WonCargoGraceTest do
  use ExUnit.Case, async: true

  alias TijaraTides.Domain.{
    Game,
    State,
    Warehouse,
    WarehouseWorld,
    CargoLots,
    CompanyFinanceWorld,
    AuctionWorld
  }

  alias TijaraTides.Domain.Services.WarehouseLiquidation
  @day 86_400_000

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

  defp lease(c, s, id, owner, blocks) do
    {:ok, s, _} =
      WarehouseWorld.lease(
        s,
        State.get(s, "accounts", owner),
        %{
          "port" => "Jakarta",
          "storage" => "dry",
          "blocks" => blocks,
          "days" => 1,
          "price" => Warehouse.quote(WarehouseWorld.used(s, "Jakarta", "dry"), "dry", blocks, 1)
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

  defp allocation(c, delayed \\ 0) do
    s =
      lease(c, c.state, "original", "a", 1)
      |> stock("original", [{"lumber", 30, nil, 100}, {"lumber", 30, nil, 100}])

    won = List.last(State.get(s, "warehouses", "original")["cargo"])
    s = if delayed > 0, do: %{s | clock_ms: @day + delayed}, else: s
    {WarehouseWorld.award_storage(s, "original", "lot", [won], c.catalogue), won}
  end

  test "won stock keeps its lot identity and shares physical capacity without duplicate allocations",
       c do
    {s, won} = allocation(c)
    child = State.get(s, "warehouses", "award:lot")
    assert child["cargo"] == [won]
    assert child["expires_ms"] == @day
    assert child["award_grace"]
    assert WarehouseWorld.used(s, "Jakarta", "dry") == 1
    assert WarehouseWorld.pools(s)["Jakarta|dry"] == 1

    claim =
      TijaraTides.Domain.Warehouse.Claim.new(
        id: "over",
        kind: :order,
        company_id: "aco",
        warehouse_id: "original",
        good: "lumber",
        quantity: 3,
        side: "buy"
      )

    assert {:error, :warehouse_capacity} = WarehouseWorld.back_order(s, claim, c.catalogue)
    claim = %{claim | warehouse_id: "award:lot", quantity: 1}
    assert {:error, :warehouse_expired} = WarehouseWorld.back_order(s, claim, c.catalogue)

    assert {:error, :warehouse_occupied} =
             WarehouseWorld.release(s, State.get(s, "accounts", "a"), "original", 1, c.catalogue)
  end

  test "late settlement gives only the won lot a new grace deadline", c do
    {s, _} = allocation(c, 10_000)
    s = %{s | clock_ms: @day + 43_200_000} |> WarehouseWorld.advance(c.catalogue)
    assert WarehouseLiquidation.pool(s, "original")["status"] == "liquidating"
    assert WarehouseLiquidation.pool(s, "original")["grace_end_ms"] == @day + 43_200_000
    assert WarehouseLiquidation.pool(s, "award:lot")["status"] == "grace"
    assert WarehouseLiquidation.pool(s, "award:lot")["grace_end_ms"] == @day + 43_210_000
    assert Enum.any?(AuctionWorld.all(s), &(&1.warehouse_id == "original"))
    refute Enum.any?(AuctionWorld.all(s), &(&1.warehouse_id == "award:lot"))
    assert WarehouseWorld.used(s, "Jakarta", "dry") == 1
  end

  test "replacement preserves cargo and group footprint, pays grace charges, and allows a later ordinary expiry",
       c do
    {s, won} = allocation(c, 10_000)
    s = %{s | clock_ms: @day + 43_200_000} |> WarehouseWorld.advance(c.catalogue)
    original = WarehouseLiquidation.pool(s, "original")
    offer = WarehouseWorld.replacement_quote(s, "award:lot", 1, c.catalogue)
    assert offer.blocks == 1

    assert offer.rent ==
             Warehouse.quote(WarehouseWorld.used(s, "Jakarta", "dry") - 1, "dry", 1, 1)

    before = State.get(s, "companies", "aco")["cash"]

    {:ok, replaced, reply} =
      WarehouseWorld.replace_award(
        s,
        State.get(s, "accounts", "a"),
        %{"warehouse" => "award:lot", "days" => 1, "price" => offer.rent},
        "replacement",
        c.catalogue
      )

    assert State.get(replaced, "warehouses", "award:lot") == nil
    assert State.get(replaced, "warehouses", "replacement")["cargo"] == [won]
    refute State.get(replaced, "warehouses", "replacement")["award_grace"]

    assert State.get(replaced, "companies", "aco")["cash"] ==
             before - offer.rent - reply["charges"]

    assert reply["charges"] > 0

    assert WarehouseLiquidation.pool(replaced, "award:lot")["replacement_paid"] ==
             reply["charges"]

    assert WarehouseLiquidation.pool(replaced, "original") == original
    assert WarehouseWorld.used(replaced, "Jakarta", "dry") == 1
    t = State.get(replaced, "warehouses", "replacement")["expires_ms"]
    expired = %{replaced | clock_ms: t} |> WarehouseWorld.advance(c.catalogue)
    assert WarehouseLiquidation.pool(expired, "replacement")["status"] == "grace"
  end

  test "insufficient replacement funds, foreign ownership and inclusive deadline reject unchanged",
       c do
    {s, _} = allocation(c)
    assert WarehouseWorld.replacement_quote(s, "award:lot", 1, c.catalogue) == nil
    s = %{s | clock_ms: @day + 1000} |> WarehouseWorld.advance(c.catalogue)
    offer = WarehouseWorld.replacement_quote(s, "award:lot", 1, c.catalogue)
    cmd = %{"warehouse" => "award:lot", "days" => 1, "price" => offer.rent}
    company = State.get(s, "companies", "aco")

    s =
      CompanyFinanceWorld.post(s, "aco", "test_funds", [
        {"cash_available", -(company["cash"] - company["reserved"])},
        {"capital", company["cash"] - company["reserved"]}
      ])

    assert {:error, :insufficient_cash} =
             WarehouseWorld.replace_award(
               s,
               State.get(s, "accounts", "a"),
               cmd,
               "replacement",
               c.catalogue
             )

    assert {:error, :warehouse_invalid} =
             WarehouseWorld.replace_award(
               s,
               State.get(s, "accounts", "b"),
               cmd,
               "replacement",
               c.catalogue
             )

    assert State.get(s, "warehouses", "replacement") == nil
    assert State.get(s, "warehouses", "award:lot")["cargo"] != []
    deadline = %{s | clock_ms: @day + 43_200_000}

    assert {:error, :warehouse_replacement_closed} =
             WarehouseWorld.replace_award(
               deadline,
               State.get(s, "accounts", "a"),
               cmd,
               "replacement",
               c.catalogue
             )
  end

  test "timely prepaid renewal extends award coverage without creating new rent assets", c do
    {s, _} = allocation(c)

    price =
      Warehouse.extension_rate(
        WarehouseWorld.fetch(s, "original"),
        WarehouseWorld.used(s, "Jakarta", "dry")
      )

    {:ok, s, _} =
      WarehouseWorld.renew(
        s,
        State.get(s, "accounts", "a"),
        %{"warehouse" => "original", "days" => 1, "price" => price},
        true
      )

    assert State.get(s, "warehouses", "award:lot")["expires_ms"] == 2 * @day
    s = %{s | clock_ms: @day} |> WarehouseWorld.advance(c.catalogue)
    assert State.get(s, "warehouses", "award:lot")["expires_ms"] == 2 * @day
    assert State.get(s, "warehouses", "award:lot")["prepaid"] == 0
    assert WarehouseLiquidation.pool(s, "award:lot") == nil
    assert WarehouseWorld.used(s, "Jakarta", "dry") == 1
  end

  test "replacement retains standing-order priority and locked auction terms", c do
    {s, _} = allocation(c)
    s = stock(s, "award:lot", [{"whisky", 1, nil, 100}])
    a = State.get(s, "accounts", "a")

    {:ok, s, _} =
      TijaraTides.Domain.Services.Exchange.place(
        s,
        a,
        %{
          "warehouse" => "award:lot",
          "good" => "lumber",
          "side" => "sell",
          "quantity" => 10,
          "price" => 1_000_000
        },
        "order",
        c.catalogue
      )

    s = %{s | clock_ms: @day + 1000} |> WarehouseWorld.advance(c.catalogue)

    {:ok, s, _} =
      TijaraTides.Domain.Services.Auctions.consign(
        s,
        a,
        %{"warehouse" => "award:lot", "good" => "whisky", "quantity" => 1, "price" => 1_000_000},
        "resale",
        c.catalogue,
        "locked-seed"
      )

    order = TijaraTides.Domain.OrderBookWorld.fetch(s, "order")
    auction = AuctionWorld.fetch(s, "resale")
    quote = WarehouseWorld.replacement_quote(s, "award:lot", 1, c.catalogue)

    {:ok, next, _} =
      WarehouseWorld.replace_award(
        s,
        a,
        %{"warehouse" => "award:lot", "days" => 1, "price" => quote.rent},
        "replacement",
        c.catalogue
      )

    assert TijaraTides.Domain.OrderBookWorld.fetch(next, "order") == %{
             order
             | warehouse_id: "replacement"
           }

    assert AuctionWorld.fetch(next, "resale") == %{auction | warehouse_id: "replacement"}

    assert Enum.all?(
             WarehouseWorld.fetch(next, "replacement").reservations,
             &(&1.warehouse_id == "replacement")
           )
  end
end
