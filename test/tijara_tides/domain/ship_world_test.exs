defmodule TijaraTides.Domain.ShipWorldTest do
  use ExUnit.Case, async: true
  alias TijaraTides.Domain.{Ship, ShipWorld, ChangeSet, LotIdsExhausted}
  alias Ship.{CargoBatch, Rows}

  defp hull do
    %Ship{
      id: "s",
      company_id: "c",
      name: "Vessel",
      class: "general",
      status: "docked",
      port: "Jakarta",
      cargo: [],
      book_value: 1000,
      build_value: 1000,
      built_ms: 0,
      fuel_total: 0,
      fuel_burned: 0,
      crew_remainder: 0,
      last_cost_ms: 0
    }
  end

  defp world(ship, ids \\ []) do
    %{
      clock_ms: 10,
      entities: %{
        "ships" => %{ship.id => Rows.encode(ship)},
        "ship_instructions" => %{
          "instruction" => %{"id" => "instruction", "ship_id" => "s", "status" => "planned"},
          "other" => %{"id" => "other", "ship_id" => "other-ship", "status" => "planned"}
        }
      },
      lot_allocation: ids,
      new_lots: [%{"id" => "earlier"}]
    }
  end

  test "legacy omitted hull fields survive a codec round trip" do
    row = Rows.encode(hull())

    for field <- ~w(voyage_path voyage_speedup paid_canals berth_queued_ms pending_side) do
      refute Map.has_key?(row, field)
    end

    assert Rows.encode(Rows.decode(row)) == row
  end

  test "hull writes preserve automation and split lots append exact lineage" do
    cargo = %CargoBatch{
      good: "lumber",
      quantity: 5,
      lot_id: "parent",
      expires_ms: 100,
      unit_cost: 37
    }

    state = world(%{hull() | cargo: [cargo]}, ["sold", "kept", "unused"])
    {next, [sold]} = ShipWorld.unload_cargo(state, "s", "lumber", 2)

    assert sold == %{
             "good" => "lumber",
             "quantity" => 2,
             "lot_id" => "sold",
             "expires_ms" => 100,
             "unit_cost" => 37
           }

    assert next.lot_allocation == ["unused"]
    assert Enum.map(next.new_lots, & &1["id"]) == ["earlier", "sold", "kept"]
    assert Enum.map(tl(next.new_lots), & &1["parent_lot_id"]) == ["parent", "parent"]
    assert next.entities["ship_instructions"] == state.entities["ship_instructions"]
    assert ShipWorld.fetch(next, "s").cargo == [%{cargo | quantity: 3, lot_id: "kept"}]
    assert ChangeSet.since(state, next) == %{{"ships", "s"} => :put}
    assert ChangeSet.assert_complete!(state, next) == :ok
  end

  test "exhausted allocation can retry without partial world mutations" do
    cargo = %CargoBatch{good: "lumber", quantity: 5, lot_id: "parent"}
    state = world(%{hull() | cargo: [cargo]}, ["only-one"])
    assert_raise LotIdsExhausted, fn -> ShipWorld.unload_cargo(state, "s", "lumber", 2) end
    assert ShipWorld.fetch(state, "s").cargo == [cargo]
    assert state.lot_allocation == ["only-one"]
  end

  test "retirement reads committed children and cancellation deletes only owned automation" do
    state = world(hull())
    assert_raise ArgumentError, fn -> ShipWorld.retire(state, "s") end
    cancelled = ShipWorld.cancel_automation(state, "s")
    assert Map.keys(cancelled.entities["ship_instructions"]) == ["other"]
    assert ChangeSet.since(state, cancelled)[{"ship_instructions", "instruction"}] == :delete
    retired = ShipWorld.retire(cancelled, "s")
    assert retired.entities["ships"] == %{}
    assert Map.keys(retired.entities["ship_instructions"]) == ["other"]
    assert ChangeSet.assert_complete!(state, retired) == :ok
  end

  test "typed berth cancellation retains retry cooldown" do
    trade = %TijaraTides.Domain.Trade{
      ship_id: "s",
      side: "buy",
      good: "lumber",
      quantity: 1,
      limit: 10
    }

    queued = Ship.queue_trade(%{hull() | berth_retry_ms: 20}, trade, 10)
    assert queued.berth_queued_ms == nil
    cancelled = Ship.cancel_pending_trade(queued)
    assert cancelled.berth_retry_ms == 20
    assert Ship.request_berth(cancelled, 19) == cancelled
    assert Ship.request_berth(cancelled, 20).berth_queued_ms == 20
  end
end
