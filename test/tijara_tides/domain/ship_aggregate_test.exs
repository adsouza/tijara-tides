defmodule TijaraTides.Domain.ShipAggregateTest do
  use ExUnit.Case, async: true
  alias TijaraTides.Domain.Ship
  alias Ship.{VisitOrder, CargoBatch}

  defp vessel do
    %Ship{
      id: "s",
      company_id: "c",
      class: "tanker",
      status: "docked",
      port: "Dubai",
      cargo: [],
      book_value: 5_000_000,
      build_value: 5_000_000,
      built_ms: 0,
      fuel_total: 0,
      fuel_burned: 0,
      crew_remainder: 0,
      last_cost_ms: 0
    }
  end

  test "the root forbids overlapping operations and mixed or overloaded liquid cargo" do
    catalogue = TijaraTides.Infrastructure.GameCatalogue.all()
    crude = %{"good" => "crude_oil", "quantity" => 1}
    fuel = %{"good" => "refined_fuel", "quantity" => 1}
    ship = Ship.record_purchase(vessel(), [crude], 0, 0, catalogue)
    assert ship.status == "loading"
    assert_raise ArgumentError, fn -> Ship.record_purchase(ship, [crude], 0, 0, catalogue) end

    assert_raise ArgumentError, fn ->
      Ship.record_purchase(vessel(), [crude, fuel], 0, 0, catalogue)
    end

    assert_raise ArgumentError, fn ->
      Ship.record_purchase(vessel(), [%{crude | "quantity" => 1_000_000}], 0, 0, catalogue)
    end

    assert_raise ArgumentError, fn ->
      Ship.begin_voyage(ship, "Singapore", %{"duration_ms" => 1000}, 0, 600)
    end
  end

  test "sale owns the split, preserves cost and expiry, and rejects invalid quantities" do
    state = %{clock_ms: 0}
    {state, batch} = TijaraTides.Domain.CargoLots.create(state, "crude_oil", 4, 90_000)
    batch = Map.merge(batch, %{"good" => "crude_oil", "unit_cost" => 123})
    ship = %{vessel() | cargo: [CargoBatch.from_row(batch)]}

    for quantity <- [-1, 0, 5, 1.5] do
      assert_raise ArgumentError, fn -> Ship.record_sale(state, ship, "crude_oil", quantity) end
    end

    assert_raise ArgumentError, fn -> Ship.record_sale(state, ship, "grain", 1) end
    {changed, next, [sold]} = Ship.record_sale(state, ship, "crude_oil", 2)
    [remaining] = next.cargo
    assert next.status == "unloading"

    for part <- [sold, remaining] do
      assert part.quantity == 2
      assert part.unit_cost == 123
      assert part.expires_ms == 90_000
      assert part.good == "crude_oil"
      assert part.lot_id != batch["lot_id"]

      assert Enum.find(changed.new_lots, &(&1["id"] == part.lot_id))["parent_lot_id"] ==
               batch["lot_id"]
    end

    assert sold.lot_id != remaining.lot_id
    {_, empty, [whole]} = Ship.record_sale(state, ship, "crude_oil", 4)
    assert empty.cargo == []
    assert CargoBatch.to_row(whole) == batch
  end

  test "arrival burns fuel once and preserves the aggregate's automation" do
    plan = %Ship.RoutePlan{header: %{"status" => "running"}}
    ship = %{vessel() | route_plan: plan}
    ship = Ship.begin_voyage(ship, "Singapore", %{"duration_ms" => 1000, "fuel" => 200}, 0, 600)
    {arrived, effects} = Ship.advance(ship, 1000, 1000, false, 600, ship.book_value)
    assert arrived.status == "docked"
    assert arrived.port == "Singapore"
    assert arrived.route_plan == plan
    assert effects.fuel == 200
    {_, later} = Ship.advance(arrived, 2000, 1000, false, 600, ship.book_value)
    assert later.fuel == 0
  end

  test "visit fill progress enforces quantity and optional budget without changing terms" do
    order = %VisitOrder{
      status: "planned",
      quantity_mode: "fixed",
      quantity: 5,
      filled: 0,
      spent: 0,
      budget: 100,
      limit: 30
    }

    partial = VisitOrder.record_fill(order, 2, 60)
    assert partial.filled == 2
    assert partial.limit == 30
    assert_raise ArgumentError, fn -> VisitOrder.record_fill(partial, 4, 0) end
    assert_raise ArgumentError, fn -> VisitOrder.record_fill(partial, 1, 50) end
    complete = VisitOrder.record_fill(partial, 3, 40)
    assert complete.status == "filled"
    assert_raise ArgumentError, fn -> VisitOrder.record_fill(complete, 1, 0) end
  end

  test "cargo decoding preserves every persisted field and rejects unrecognized fields" do
    row = %{
      "lot_id" => "lot:1",
      "good" => "grain",
      "quantity" => 7,
      "unit_cost" => 123,
      "expires_ms" => 456
    }

    batch = CargoBatch.from_row(row)
    assert %CargoBatch{quantity: 7, unit_cost: 123, expires_ms: 456} = batch
    assert CargoBatch.to_row(batch) == row
    assert_raise ArgumentError, fn -> CargoBatch.from_row(Map.put(row, "future_column", 1)) end
    assert_raise ArgumentError, fn -> CargoBatch.from_row(Map.delete(row, "quantity")) end
  end
end
