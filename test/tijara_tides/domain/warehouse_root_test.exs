defmodule TijaraTides.Domain.WarehouseRootTest do
  use ExUnit.Case, async: true
  alias TijaraTides.Domain.{Warehouse, WarehouseWorld, ChangeSet, LotIdsExhausted}
  alias Warehouse.{Claim, Reservation, Rows, ReservationRows}
  alias TijaraTides.Domain.Ship.CargoBatch
  @day 86_400_000

  defp lease do
    %Warehouse{
      id: "w",
      company_id: "c",
      port: "p",
      storage: "dry",
      good: nil,
      blocks: 10,
      started_ms: 0,
      expires_ms: @day,
      rent: 1000,
      prepaid: 1000,
      protected_ms: 0
    }
  end

  defp catalogue do
    %{
      "goods" => %{
        "lumber" => %{
          "id" => "lumber",
          "hold" => "dry",
          "volume_l" => 1000,
          "reference_cents" => 100
        }
      }
    }
  end

  defp claim(id, n) do
    Claim.new(
      id: id,
      company_id: "c",
      warehouse_id: "w",
      kind: :order,
      side: "sell",
      good: "lumber",
      quantity: n
    )
  end

  defp stock do
    %CargoBatch{good: "lumber", quantity: 10, lot_id: "parent", expires_ms: 100, unit_cost: 23}
  end

  test "accrual and partial release split prepaid rent without double charging" do
    {w, expense} = Warehouse.accrue(lease(), div(@day, 2))
    assert expense == 500
    assert Warehouse.accrue(w, div(@day, 2)) == {w, 0}
    {w, amounts} = Warehouse.release_blocks(w, 5, div(@day, 2), catalogue())
    assert {w.blocks, w.rent, w.prepaid} == {5, 500, 250}
    assert amounts == %{forfeited: 250, refund: 125}

    assert_raise ArgumentError, fn ->
      Warehouse.release_blocks(%{w | protected_ms: @day}, 1, div(@day, 2), catalogue())
    end
  end

  test "paid renewal rolls once and a queued term cannot be paid twice" do
    locked = Warehouse.lock_quote(lease(), @day - 1, 10)
    paid = Warehouse.pay_renewal(locked, 3, @day - 1)
    assert_raise ArgumentError, fn -> Warehouse.pay_renewal(paid, 3, @day - 1) end
    {next, expense} = Warehouse.roll_term(paid, @day, false)
    assert expense == 1000

    assert {next.started_ms, next.expires_ms, next.prepaid} ==
             {@day, @day * 4, locked.renewal_rate * 3}

    assert Warehouse.roll_term(next, @day, false) == {next, 0}
    assert Warehouse.roll_term(paid, @day, true) == {paid, 0}
  end

  test "reservation transitions update the root so subsequent admissions see exclusive claims" do
    w = %{lease() | cargo: [stock()]}
    {:ok, backed} = Warehouse.back_order(w, claim("a", 6), 0, catalogue())
    assert length(backed.warehouse.reservations) == 1

    assert {:error, :insufficient_cargo} =
             Warehouse.back_order(backed.warehouse, claim("b", 5), 0, catalogue())

    consumed = Warehouse.consume_order(backed.warehouse, claim("a", 6), 2)
    assert hd(consumed.warehouse.reservations).quantity == 4
    assert {:ok, _} = Warehouse.back_order(consumed.warehouse, claim("b", 6), 0, catalogue())
    complete = Warehouse.consume_order(consumed.warehouse, claim("a", 4), 4)
    assert complete.delete == ["exchange:a"]
    assert complete.warehouse.reservations == []

    assert_raise ArgumentError, fn ->
      Warehouse.consume_order(complete.warehouse, claim("a", 1), 1)
    end
  end

  test "pruning allocates fresh stock by priority and explicitly removes invalid owners" do
    r = %Reservation{
      id: "first",
      warehouse_id: "w",
      company_id: "c",
      ship_id: "s",
      good: "lumber",
      kind: "stock",
      quantity: 7,
      created_ms: 0,
      stop_id: nil
    }

    w = %{
      lease()
      | cargo: [stock()],
        reservations: [r, %{r | id: "second", created_ms: 1}, %{r | id: "invalid", created_ms: 2}]
    }

    result = Warehouse.prune_reservations(w, 0, MapSet.new(["first", "second"]))

    assert Enum.map(result.warehouse.reservations, &{&1.id, &1.quantity}) == [
             {"first", 7},
             {"second", 3}
           ]

    assert Enum.map(result.put, &{&1.id, &1.quantity}) == [{"second", 3}]
    assert result.delete == ["invalid"]
    expired = Warehouse.prune_reservations(result.warehouse, 100, MapSet.new(["first", "second"]))
    assert expired.delete == ["first", "second"]
    assert expired.warehouse.reservations == []
  end

  test "clearance cannot exceed cost and waits for handling protection" do
    w = %{lease() | cargo: [stock()], protected_ms: @day * 2}
    assert Warehouse.clearance(w, @day + div(@day, 2), false, catalogue()) == nil

    assert %{cost: 230, value: 230, charges: 230} =
             Warehouse.clearance(w, @day * 2, false, catalogue())
  end

  test "world fill preserves stale stock for disposal, explicit child writes and lineage" do
    stale = %{stock() | lot_id: "stale", expires_ms: 0, quantity: 1}
    w = %{lease() | cargo: [stale, stock()]}
    {:ok, t} = Warehouse.back_order(w, claim("a", 4), 0, catalogue())
    row = Rows.encode(t.warehouse)
    refute Map.has_key?(row, "reservations")
    assert Rows.encode(Rows.decode(row)) == row

    state = %{
      clock_ms: 0,
      entities: %{
        "warehouses" => %{"w" => row},
        "warehouse_reservations" => Map.new(t.put, &{&1.id, ReservationRows.encode(&1)})
      },
      lot_allocation: ["part", "rest"],
      new_lots: [%{"id" => "earlier"}]
    }

    assert_raise LotIdsExhausted, fn ->
      WarehouseWorld.exchange_out(%{state | lot_allocation: ["part"]}, claim("a", 4), 2)
    end

    {next, [cargo]} = WarehouseWorld.exchange_out(state, claim("a", 4), 2)
    assert cargo == %{stock() | lot_id: "part", quantity: 2}

    assert WarehouseWorld.fetch(next, "w").cargo == [
             %{stock() | lot_id: "rest", quantity: 8},
             stale
           ]

    assert hd(WarehouseWorld.fetch(next, "w").reservations).quantity == 2
    assert Enum.map(next.new_lots, & &1["id"]) == ["earlier", "part", "rest"]
    assert Enum.all?(tl(next.new_lots), &(&1["parent_lot_id"] == "parent"))

    assert ChangeSet.since(state, next) == %{
             {"warehouses", "w"} => :put,
             {"warehouse_reservations", "exchange:a"} => :put
           }

    assert ChangeSet.assert_complete!(state, next) == :ok
  end

  test "reservation-only transitions leave legacy lease rows untouched" do
    row =
      Rows.encode(%{lease() | cargo: [stock()]})
      |> Map.drop(~w(display_number renewal_rate next_rent next_days auto_days auto_cap))

    state = %{clock_ms: 0, entities: %{"warehouses" => %{"w" => row}}}
    {:ok, next} = WarehouseWorld.back_order(state, claim("a", 4), catalogue())
    assert next.entities["warehouses"]["w"] == row
    assert ChangeSet.since(state, next) == %{{"warehouse_reservations", "exchange:a"} => :put}
    assert ChangeSet.assert_complete!(state, next) == :ok
  end
end
