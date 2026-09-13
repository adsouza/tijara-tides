defmodule TijaraTides.Domain.WarehouseTest do
  use ExUnit.Case, async: true
  alias TijaraTides.Domain.{Game, Warehouse, CompanyFinance, CargoLots, Ship}

  setup do
    catalogue = TijaraTides.Infrastructure.GameCatalogue.all()
    state = Game.initialize(%{entities: %{}, clock_ms: 0, epoch: 1, revision: 0}, catalogue)
    {:ok, state, _} = Game.seed_invite(state, "invite")
    {:ok, state, _} = Game.redeem(state, "invite", "session", %{id: "account", wall_ms: 0})

    {:ok, state, _} =
      TijaraTides.CompanyFixture.create_company(
        state,
        Game.get(state, "accounts", "account"),
        "Storage",
        "Jakarta",
        "general",
        %{id: "company", catalogue: catalogue}
      )

    %{state: state, account: Game.get(state, "accounts", "account"), catalogue: catalogue}
  end

  defp lease(c, state, blocks \\ 10, storage \\ "dry", good \\ nil, id \\ "lease") do
    cmd = %{
      "port" => "Jakarta",
      "storage" => storage,
      "blocks" => blocks,
      "days" => 1,
      "good" => good,
      "price" => Warehouse.quote(Warehouse.used(state, "Jakarta", storage), storage, blocks, 1)
    }

    {:ok, state, _} = Warehouse.lease(state, c.account, cmd, id, c.catalogue)
    state
  end

  # Put batches straight into a lease so a test can choose their expiry.
  defp stock(state, id, batches) do
    w = Warehouse.from_row(Game.get(state, "warehouses", id))

    {cargo, state} =
      Enum.map_reduce(batches, state, fn {good, quantity, expires}, state ->
        {state, lot} = CargoLots.create(state, good, quantity, expires)

        {TijaraTides.Domain.Ship.CargoBatch.from_row(
           Map.merge(lot, %{"good" => good, "unit_cost" => 100, "expires_ms" => expires})
         ), state}
      end)

    state =
      TijaraTides.Domain.State.put(
        state,
        "warehouses",
        id,
        Warehouse.to_row(%{w | cargo: cargo})
      )

    CompanyFinance.post(state, "company", "purchase", [
      {"inventory", Enum.sum(for b <- cargo, do: b.quantity * b.unit_cost)},
      {"cash_available", -Enum.sum(for b <- cargo, do: b.quantity * b.unit_cost)}
    ])
  end

  defp stocked(c) do
    state = lease(c, c.state)
    {state, batch} = CargoLots.create(state, "lumber", 10, nil)
    batch = Map.merge(batch, %{"unit_cost" => 120, "good" => "lumber"})
    state = Ship.load_cargo(state, "company:1", [batch], 0, c.catalogue)

    state =
      CompanyFinance.post(state, "company", "purchase", [
        {"inventory", 1200},
        {"cash_available", -1200}
      ])

    Game.advance(state, 5000, c.catalogue)
  end

  defp transfer(c, state, side, quantity) do
    Warehouse.transfer(
      state,
      c.account,
      %{
        "warehouse" => "lease",
        "ship" => "company:1",
        "good" => "lumber",
        "quantity" => quantity,
        "side" => side
      },
      c.catalogue
    )
  end

  test "progressive finite capacity quotes and stale prices", c do
    assert Warehouse.quote(800, "dry", 10, 1) > Warehouse.quote(0, "dry", 10, 1)
    assert Warehouse.quote(999, "dry", 2, 1) == nil
    assert Warehouse.quote(0, "dry", -1, 1) == nil

    assert {:error, :price_changed} =
             Warehouse.lease(
               c.state,
               c.account,
               %{
                 "port" => "Jakarta",
                 "storage" => "dry",
                 "blocks" => 1,
                 "days" => 1,
                 "price" => 0
               },
               "x",
               c.catalogue
             )
  end

  test "rent remains an asset, amortizes, and unused released space refunds half", c do
    state = lease(c, c.state)
    rent = Game.get(state, "warehouses", "lease")["rent"]

    assert Game.get(state, "companies", "company")["profit"] ==
             Game.get(c.state, "companies", "company")["profit"]

    state = Warehouse.advance(%{state | clock_ms: 43_200_000}, c.catalogue)
    assert Game.get(state, "warehouses", "lease")["prepaid"] == div(rent, 2)
    {:ok, state, reply} = Warehouse.release(state, c.account, "lease", 5, c.catalogue)
    assert reply["refund"] > 0
    assert Game.get(state, "warehouses", "lease")["blocks"] == 5
    state = Warehouse.advance(%{state | clock_ms: 86_400_000}, c.catalogue)
    assert Game.get(state, "warehouses", "lease")["prepaid"] == 0
  end

  test "partial transfers conserve cost, quantity and lineage; handling protects space", c do
    state = stocked(c)
    [parent] = Game.get(state, "ships", "company:1")["cargo"]
    {:ok, state, _} = transfer(c, state, "store", 4)
    [stored] = Game.get(state, "warehouses", "lease")["cargo"]
    assert stored["quantity"] == 4
    assert stored["unit_cost"] == 120
    refute stored["lot_id"] == parent["lot_id"]

    assert {:error, :warehouse_occupied} =
             Warehouse.release(state, c.account, "lease", 10, c.catalogue)

    assert Game.get(state, "ships", "company:1")["status"] == "unloading"
    state = Game.advance(state, 2000, c.catalogue)
    {:ok, state, _} = transfer(c, state, "collect", 4)
    assert Game.get(state, "warehouses", "lease")["cargo"] == []
    assert Ship.cargo_available(state, "company:1", "lumber") == 10

    assert Enum.any?(
             Game.get(state, "ships", "company:1")["cargo"],
             &(&1["lot_id"] == stored["lot_id"])
           )

    assert Warehouse.to_row(Warehouse.from_row(Game.get(state, "warehouses", "lease"))) ==
             Game.get(state, "warehouses", "lease")
  end

  test "expiry forbids deposits and clears remaining stock after grace", c do
    state = stocked(c)
    {:ok, state, _} = transfer(c, state, "store", 4)
    state = Game.advance(state, 2000, c.catalogue)
    state = Warehouse.advance(%{state | clock_ms: 86_400_000}, c.catalogue)
    assert {:error, :warehouse_expired} = transfer(c, state, "store", 1)
    assert {:ok, _, _} = transfer(c, state, "collect", 1)
    state = Warehouse.advance(%{state | clock_ms: 129_600_000}, c.catalogue)
    assert Game.get(state, "warehouses", "lease") == nil
  end

  test "ownership and berth availability are checked before moving cargo", c do
    state = stocked(c)

    assert {:error, :warehouse_invalid} =
             Warehouse.transfer(
               state,
               %{"company_id" => "other"},
               %{"warehouse" => "lease"},
               c.catalogue
             )

    catalogue = put_in(c.catalogue, ["ports", "Jakarta", "berth_count"], 1)

    state =
      TijaraTides.Domain.BerthFixture.update(state, "company:2", %{
        berth_granted_ms: state.clock_ms
      })

    assert {:error, :warehouse_berth_busy} =
             transfer(%{c | catalogue: catalogue}, state, "store", 1)

    refute Map.has_key?(TijaraTides.Domain.Visibility.public(state, catalogue), "warehouses")
    assert TijaraTides.Domain.Visibility.private(state, c.account)["warehouses"]["lease"]
  end

  test "collection never hands over lots the availability count excluded", c do
    state = lease(c, c.state)
    state = stock(state, "lease", [{"lumber", 5, 1_000}, {"lumber", 5, 10_000_000}])
    state = %{state | clock_ms: 5_000}

    # Five fresh lots are on offer, so five is accepted; the expired five must stay put.
    assert {:error, :insufficient_cargo} = transfer(c, state, "collect", 6)
    {:ok, state, _} = transfer(c, state, "collect", 5)

    assert Enum.map(Game.get(state, "warehouses", "lease")["cargo"], & &1["expires_ms"]) ==
             [1_000]

    assert Enum.all?(
             Game.get(state, "ships", "company:1")["cargo"],
             &(&1["expires_ms"] == 10_000_000)
           )
  end

  test "perishables in storage spoil at cost and leave the ledger balanced", c do
    state = lease(c, c.state, 10, "reefer")
    state = stock(state, "lease", [{"fruit", 4, 20_000}, {"fruit", 6, 90_000_000}])

    # Rent amortizes on the same tick, so net it out to see the spoilage on its own.
    profit = fn s -> Game.get(s, "companies", "company")["profit"] end
    prepaid = fn s -> Game.get(s, "warehouses", "lease")["prepaid"] end
    before = profit.(state)
    held = prepaid.(state)

    state = Warehouse.advance(%{state | clock_ms: 50_000}, c.catalogue)

    assert Enum.map(Game.get(state, "warehouses", "lease")["cargo"], & &1["quantity"]) == [6]
    assert profit.(state) == before - 400 - (held - prepaid.(state))

    # A tick with nothing expiring moves profit by rent alone.
    steady = profit.(state)
    held = prepaid.(state)
    state = Warehouse.advance(%{state | clock_ms: 60_000}, c.catalogue)
    assert profit.(state) == steady - (held - prepaid.(state))
  end

  test "liquid leases bind to one cargo type and refuse foreign goods", c do
    assert {:error, :incompatible_cargo} =
             Warehouse.lease(
               c.state,
               c.account,
               %{
                 "port" => "Jakarta",
                 "storage" => "liquid",
                 "blocks" => 1,
                 "days" => 1,
                 "good" => "lumber",
                 "price" => Warehouse.quote(0, "liquid", 1, 1)
               },
               "x",
               c.catalogue
             )

    state = lease(c, c.state, 2, "liquid", "crude_oil")
    w = Warehouse.from_row(Game.get(state, "warehouses", "lease"))
    assert w.good == "crude_oil"
    assert Warehouse.compatible?(w, c.catalogue["goods"]["crude_oil"])
    refute Warehouse.compatible?(w, c.catalogue["goods"]["refined_fuel"])
    refute Warehouse.compatible?(w, c.catalogue["goods"]["lumber"])
  end

  test "malformed lease terms are rejected as invalid, not as a full pool", c do
    for cmd <- [
          %{"storage" => "chilled", "blocks" => 1, "days" => 1},
          %{"storage" => "dry", "blocks" => 0, "days" => 1},
          %{"storage" => "dry", "blocks" => 1, "days" => 2}
        ] do
      assert {:error, :warehouse_invalid} =
               Warehouse.lease(
                 c.state,
                 c.account,
                 Map.merge(cmd, %{"port" => "Jakarta", "price" => 0}),
                 "x",
                 c.catalogue
               )
    end

    assert {:error, :warehouse_capacity} =
             Warehouse.lease(
               c.state,
               c.account,
               %{
                 "port" => "Jakarta",
                 "storage" => "dry",
                 "blocks" => 1001,
                 "days" => 1,
                 "price" => 0
               },
               "x",
               c.catalogue
             )
  end

  test "a bankrupt or overdue company cannot cash out leased space", c do
    state = lease(c, c.state)

    overdue =
      TijaraTides.Domain.State.put(
        state,
        "companies",
        "company",
        Map.put(Game.get(state, "companies", "company"), "unpaid", 500)
      )

    assert {:error, :insufficient_cash} =
             Warehouse.release(overdue, c.account, "lease", 5, c.catalogue)

    bankrupt =
      TijaraTides.Domain.State.put(
        state,
        "companies",
        "company",
        Map.put(Game.get(state, "companies", "company"), "bankruptcy_ms", 1)
      )

    assert {:error, :finance_no_company} =
             Warehouse.release(bankrupt, c.account, "lease", 5, c.catalogue)

    assert {:ok, _, _} = Warehouse.release(state, c.account, "lease", 5, c.catalogue)
  end

  test "clearance never pays out more than the abandoned cargo cost", c do
    state = lease(c, c.state)
    # Half reference for lumber is 12,500 a lot, well above the 100 a lot actually paid.
    state = stock(state, "lease", [{"lumber", 4, nil}])
    cash = Game.get(state, "companies", "company")["cash"]

    state = Warehouse.advance(%{state | clock_ms: 129_600_000}, c.catalogue)

    assert Game.get(state, "warehouses", "lease") == nil
    proceeds = Game.get(state, "companies", "company")["cash"] - cash
    assert proceeds <= 400
  end

  test "mixing expensive and cheap batches cannot lift cheap-stock clearance proceeds", c do
    state = lease(c, c.state) |> stock("lease", [{"lumber", 1, nil}, {"lumber", 1, nil}])
    row = Game.get(state, "warehouses", "lease")
    [cheap, expensive] = row["cargo"]
    row = Map.put(row, "cargo", [cheap, Map.put(expensive, "unit_cost", 50_000)])
    state = TijaraTides.Domain.State.put(state, "warehouses", "lease", row)

    state =
      CompanyFinance.post(state, "company", "purchase", [
        {"inventory", 49_900},
        {"cash_available", -49_900}
      ])

    cash = Game.get(state, "companies", "company")["cash"]
    state = Warehouse.advance(%{state | clock_ms: 129_600_000}, c.catalogue)
    assert Game.get(state, "companies", "company")["cash"] - cash <= 12_600
  end
end
