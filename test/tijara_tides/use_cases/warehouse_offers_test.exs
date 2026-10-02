defmodule TijaraTides.UseCases.WarehouseOffersTest do
  # Offered transfer quantities come from the same limits the transfer command
  # enforces: the offer is accepted, and one lot more is refused.
  use ExUnit.Case, async: true

  alias TijaraTides.Domain.{CargoLots, CompanyFinanceWorld, Game, PortCargoMarket, State}
  alias TijaraTides.Domain.{Visibility, Warehouse, WarehouseWorld}
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

    {:ok, s, _} =
      WarehouseWorld.lease(
        s,
        Game.get(s, "accounts", "a"),
        %{
          "port" => "Jakarta",
          "storage" => "dry",
          "blocks" => 10,
          "days" => 1,
          "price" => Warehouse.quote(WarehouseWorld.used(s, "Jakarta", "dry"), "dry", 10, 1)
        },
        "aw",
        cat
      )

    {s, lot} = CargoLots.create(s, "lumber", 10, nil)
    row = Game.get(s, "warehouses", "aw")

    batch =
      CargoRows.encode(
        CargoRows.decode(
          Map.merge(lot, %{"good" => "lumber", "unit_cost" => 100, "expires_ms" => nil})
        )
      )

    s =
      s
      |> State.put("warehouses", "aw", %{row | "cargo" => [batch]})
      |> CompanyFinanceWorld.post("aco", "purchase", [
        {"inventory", 1000},
        {"cash_available", -1000}
      ])

    %{s: s, definitions: definitions, cat: cat}
  end

  defp offer(c, s, side) do
    account = Game.get(s, "accounts", "a")
    view = %{public: Visibility.public(s, c.cat), private: Visibility.private(s, account)}

    GameQueries.warehouse_options(
      c.definitions,
      view,
      "Jakarta",
      %{},
      view.private["ships"]["aco:1"]
    )
    |> Map.fetch!(:leases)
    |> Enum.find(&(&1.row["id"] == "aw"))
    |> Map.fetch!(:transfers)
    |> Enum.find(%{store: 0, collect: 0}, &(&1.good == "lumber"))
    |> Map.fetch!(String.to_existing_atom(side))
  end

  defp transfer(s, side, n, cat),
    do:
      WarehouseWorld.transfer(
        s,
        Game.get(s, "accounts", "a"),
        %{
          "warehouse" => "aw",
          "ship" => "aco:1",
          "good" => "lumber",
          "quantity" => n,
          "side" => side
        },
        cat,
        :validate
      )

  defp available(s, n) do
    company = Game.get(s, "companies", "aco")
    delta = n - company["cash"] + company["reserved"]

    CompanyFinanceWorld.post(s, "aco", "test_funds", [
      {"cash_available", delta},
      {"capital", -delta}
    ])
  end

  defp exact!(c, s, side, error) do
    n = offer(c, s, side)
    assert n > 0
    assert {:ok, _, _} = transfer(s, side, n, c.cat)
    assert {:error, ^error} = transfer(s, side, n + 1, c.cat)
    n
  end

  test "the collection offer is bounded by the same stock limit the command enforces", c do
    assert exact!(c, c.s, "collect", :insufficient_cargo) == 10
  end

  test "the collection offer is bounded by the same cash limit the command enforces", c do
    handling = PortCargoMarket.handling_rate(c.cat["ports"]["Jakarta"])
    s = available(c.s, handling * 3 + div(handling, 2))
    assert exact!(c, s, "collect", :insufficient_cash) == 3
  end

  test "the storage offer is bounded by the same cargo-aboard limit the command enforces", c do
    {:ok, s, _} = transfer(c.s, "collect", 4, c.cat)
    s = %{s | clock_ms: State.get(s, "warehouses", "aw")["protected_ms"]}
    s = State.put(s, "ships", "aco:1", %{State.get(s, "ships", "aco:1") | "status" => "docked"})
    assert exact!(c, s, "store", :insufficient_cargo) == 4
  end
end
