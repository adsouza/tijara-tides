defmodule TijaraTides.UseCases.MarketOffersTest do
  # Exchange sell warehouses and auction consignments are offered from the same stock
  # and storage rules the commands enforce: the offer is accepted, one lot more is
  # refused, and nothing is offered that the command would refuse.
  use ExUnit.Case, async: true

  alias TijaraTides.Domain.{CargoLots, CompanyFinanceWorld, Game, Markets, State}
  alias TijaraTides.Domain.{Visibility, Warehouse, WarehouseWorld}
  alias TijaraTides.Domain.Services.{Auctions, Exchange}
  alias TijaraTides.Domain.Ship.CargoRows
  alias TijaraTides.UseCases.GameQueries

  setup do
    definitions = TijaraTides.UseCases.Game.definitions()
    cat = definitions.catalogue
    s = Game.initialize(%{entities: %{}, clock_ms: 0, epoch: 1, revision: 0}, cat)
    {:ok, s, _} = Game.seed_invite(s, "invite")
    {:ok, s, _} = Game.redeem(s, "invite", "session", %{id: "a", wall_ms: 0})

    {:ok, s, _} =
      TijaraTides.CompanyFixture.create_company(
        s,
        Game.get(s, "accounts", "a"),
        "a",
        "Jakarta",
        "general",
        %{id: "aco", catalogue: cat}
      )

    %{s: s, definitions: definitions, cat: cat}
  end

  # Leases dry storage for `days` and stocks it with `quantity` lots of `good`.
  defp stocked(c, good, quantity, days) do
    {:ok, s, _} =
      WarehouseWorld.lease(
        c.s,
        account(c.s),
        %{
          "port" => "Jakarta",
          "storage" => "dry",
          "blocks" => 10,
          "days" => days,
          "price" => Warehouse.quote(WarehouseWorld.used(c.s, "Jakarta", "dry"), "dry", 10, days)
        },
        "aw",
        c.cat
      )

    {s, lot} = CargoLots.create(s, good, quantity, nil)
    row = Game.get(s, "warehouses", "aw")

    batch =
      CargoRows.encode(
        CargoRows.decode(
          Map.merge(lot, %{"good" => good, "unit_cost" => 100, "expires_ms" => nil})
        )
      )

    s
    |> State.put("warehouses", "aw", %{row | "cargo" => [batch]})
    |> CompanyFinanceWorld.post("aco", "purchase", [
      {"inventory", 100 * quantity},
      {"cash_available", -100 * quantity}
    ])
  end

  defp account(s), do: Game.get(s, "accounts", "a")

  defp view(s, cat),
    do: %{
      public: Visibility.public(s, cat),
      private: Visibility.private(s, account(s)),
      markets: Markets.quotes(s, cat)
    }

  defp sell(s, cat, n),
    do:
      Exchange.place(
        s,
        account(s),
        %{
          "warehouse" => "aw",
          "good" => "lumber",
          "side" => "sell",
          "quantity" => n,
          "price" => 1_000_000
        },
        "order-#{n}",
        cat
      )

  defp consign(s, cat, n),
    do:
      Auctions.consign(
        s,
        account(s),
        %{"warehouse" => "aw", "good" => "whisky", "quantity" => n, "price" => 1_000_000},
        "consign-#{n}",
        cat,
        "seed"
      )

  test "a warehouse is offered for sell orders exactly while it holds claimable stock", c do
    s = stocked(c, "lumber", 10, 1)
    book = GameQueries.exchange_options(c.definitions, view(s, c.cat), "Jakarta", "lumber")
    assert Enum.map(book.sell_warehouses, & &1["id"]) == ["aw"]

    assert {:ok, reserved, _} = sell(s, c.cat, 10)
    assert {:error, :insufficient_cargo} = sell(s, c.cat, 11)

    # Once every lot backs an order, the warehouse is no longer offered and selling fails.
    book = GameQueries.exchange_options(c.definitions, view(reserved, c.cat), "Jakarta", "lumber")
    assert book.sell_warehouses == []
    assert {:error, :insufficient_cargo} = sell(reserved, c.cat, 1)
  end

  test "a consignment offer carries the claimable quantity the command accepts", c do
    s = stocked(c, "whisky", 3, 3)

    assert [%{good: "whisky", quantity: 3} = offer] =
             GameQueries.auction_options(c.definitions, view(s, c.cat), "Jakarta").consignable

    assert offer.warehouse["id"] == "aw"
    assert {:ok, consigned, _} = consign(s, c.cat, 3)
    assert {:error, :insufficient_cargo} = consign(s, c.cat, 4)

    # Consigned lots are reserved, so nothing more is offered or accepted.
    assert GameQueries.auction_options(c.definitions, view(consigned, c.cat), "Jakarta").consignable ==
             []

    assert {:error, :insufficient_cargo} = consign(consigned, c.cat, 1)
  end

  test "storage that ends before the next auction closes offers no consignment", c do
    s = stocked(c, "whisky", 3, 1)
    {_opens, closes} = TijaraTides.Domain.AuctionWorld.schedule(0, "Jakarta", c.cat)
    lease = WarehouseWorld.snapshot(Game.get(s, "warehouses", "aw"))
    refute Warehouse.covers?(lease, closes, 0)

    assert GameQueries.auction_options(c.definitions, view(s, c.cat), "Jakarta").consignable == []
    assert {:error, {:auction_storage, _, _}} = consign(s, c.cat, 1)
  end
end
