defmodule TijaraTides.Domain.ExchangePortionsTest do
  # Sell portions are derived from the warehouse's FEFO allocation. A transition that
  # changes a warehouse's cargo re-derives them at once, whoever owns the order.
  use ExUnit.Case, async: true

  alias TijaraTides.Domain.{CargoFreshness, CargoLots, Commands, CompanyFinanceWorld, Game}
  alias TijaraTides.Domain.{OrderBook, OrderBookWorld, State, Warehouse, WarehouseWorld}
  alias TijaraTides.Domain.Ship.{CargoBatch, CargoRows}

  setup do
    cat =
      TijaraTides.Infrastructure.GameCatalogue.all()
      |> put_in(["goods", "fruit", "shelf_ms"], 100_000_000)

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
            "fresh",
            %{id: id <> "co", catalogue: cat}
          )

        {:ok, s, _} =
          WarehouseWorld.lease(
            s,
            State.get(s, "accounts", id),
            %{
              "port" => "Jakarta",
              "storage" => "reefer",
              "blocks" => 2,
              "days" => 1,
              "price" =>
                Warehouse.quote(WarehouseWorld.used(s, "Jakarta", "reefer"), "reefer", 2, 1)
            },
            id <> "w",
            cat
          )

        s
      end)

    m = State.get(s, "markets", "Jakarta|fruit")

    s =
      State.put(s, "markets", "Jakarta|fruit", %{m | "stock" => 0, "batches" => [], "demand" => 0})

    %{s: s, cat: cat}
  end

  defp stock(s, cat, owner, groups) do
    {s, cargo} =
      Enum.reduce(groups, {s, []}, fn {n, life}, {s, cargo} ->
        {s, lot} = CargoLots.create(s, "fruit", n, life)

        batch =
          %CargoBatch{
            good: "fruit",
            quantity: n,
            lot_id: lot["lot_id"],
            expires_ms: life,
            unit_cost: 10
          }
          |> CargoFreshness.initialize(s.clock_ms, cat["goods"]["fruit"])

        {s, cargo ++ [CargoRows.encode(batch)]}
      end)

    w = State.get(s, "warehouses", owner <> "w")
    value = Enum.sum(for b <- cargo, do: b["quantity"] * 10)

    s
    |> State.put("warehouses", owner <> "w", %{w | "cargo" => cargo})
    |> CompanyFinanceWorld.post(owner <> "co", "purchase", [
      {"inventory", value},
      {"cash_available", -value}
    ])
  end

  defp command(s, cat, account, command, id) do
    {:ok, s, _} =
      Commands.execute(
        %{s | revision: s.revision + 1},
        State.get(s, "accounts", account),
        command,
        %{
          id: id,
          catalogue: cat
        }
      )

    s
  end

  defp place(s, cat, account, side, quantity, price, id),
    do:
      command(
        s,
        cat,
        account,
        %{
          "action" => "exchange_place",
          "warehouse" => account <> "w",
          "good" => "fruit",
          "side" => side,
          "quantity" => quantity,
          "price" => price
        },
        id
      )

  defp portions_current?(s, id) do
    o = OrderBookWorld.fetch(s, id)
    allocation = WarehouseWorld.order_cargo(s, OrderBook.claim(o))

    Map.new(o.portions, fn {lot, p} -> {lot, p["quantity"]} end) ==
      Map.new(allocation, &{&1.lot_id, &1.quantity})
  end

  test "cargo arriving from another company's fill re-derives the receiver's sell portions",
       %{s: s, cat: cat} do
    s =
      s
      |> stock(cat, "a", [{10, 50_000_000}])
      |> stock(cat, "b", [{10, 400_000_000}])
      |> place(cat, "b", "sell", 10, 9000, "sellB")
      |> place(cat, "b", "buy", 5, 1000, "buyB")

    assert portions_current?(s, "sellB")

    # A's command fills B's resting buy; sooner-expiring cargo enters B's warehouse.
    s = place(s, cat, "a", "sell", 5, 1000, "sellA")
    assert OrderBookWorld.fetch(s, "buyB") == nil
    assert portions_current?(s, "sellB")
  end

  test "collecting cargo re-derives the remaining sell portions", %{s: s, cat: cat} do
    s =
      s
      |> stock(cat, "a", [{10, 50_000_000}, {10, 90_000_000}])
      |> place(cat, "a", "sell", 10, 1000, "sellA")

    ship =
      State.owned(s, "ships", "company_id", "aco")
      |> Enum.find(&(&1["port"] == "Jakarta" and &1["status"] == "docked"))

    s =
      command(
        s,
        cat,
        "a",
        %{
          "action" => "warehouse_transfer",
          "warehouse" => "aw",
          "ship" => ship["id"],
          "good" => "fruit",
          "quantity" => 5,
          "side" => "collect"
        },
        "collect"
      )

    assert portions_current?(s, "sellA")
  end
end
