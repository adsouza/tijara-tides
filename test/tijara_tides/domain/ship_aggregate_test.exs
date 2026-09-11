defmodule TijaraTides.Domain.ShipAggregateTest do
  use ExUnit.Case, async: true
  alias TijaraTides.Domain.Ship
  alias Ship.VisitOrder

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

  test "sale cannot silently create or destroy cargo" do
    batch = %{"good" => "crude_oil", "quantity" => 4}
    ship = %{vessel() | cargo: [batch]}

    assert_raise ArgumentError, fn ->
      Ship.record_sale(ship, [%{batch | "quantity" => 2}], [], 0)
    end

    next = Ship.record_sale(ship, [%{batch | "quantity" => 2}], [%{batch | "quantity" => 2}], 0)
    assert next.status == "unloading"
    assert next.cargo == [%{batch | "quantity" => 2}]
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
end
