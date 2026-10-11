defmodule TijaraTides.Domain.CargoLotsTest do
  use ExUnit.Case, async: true
  alias TijaraTides.Domain.{CargoLots, LotIdsExhausted}

  test "local creation advances the cursor and appends immutable lineage records" do
    {state, first} = CargoLots.create(%{clock_ms: 42}, "fruit", 5, 100)
    {state, second} = CargoLots.create(state, "fruit", 2, 100, first["lot_id"])

    assert first == %{"lot_id" => "local-lot:1", "quantity" => 5, "expires_ms" => 100}
    assert second == %{"lot_id" => "local-lot:2", "quantity" => 2, "expires_ms" => 100}
    assert state.lot_allocation == {:local, 3}

    assert state.new_lots == [
             %{
               "id" => "local-lot:1",
               "good" => "fruit",
               "quantity" => 5,
               "expires_ms" => 100,
               "parent_lot_id" => nil,
               "created_ms" => 42
             },
             %{
               "id" => "local-lot:2",
               "good" => "fruit",
               "quantity" => 2,
               "expires_ms" => 100,
               "parent_lot_id" => "local-lot:1",
               "created_ms" => 42
             }
           ]
  end

  test "allocated IDs are consumed in order and exhaustion never falls back to local IDs" do
    {state, lot} =
      CargoLots.create(%{clock_ms: 0, lot_allocation: ["allocated"]}, "lumber", 1, nil)

    assert lot["lot_id"] == "allocated"
    assert state.lot_allocation == []
    assert_raise LotIdsExhausted, fn -> CargoLots.create(state, "lumber", 1, nil) end
  end

  test "zero demand leaves batches and allocation state untouched" do
    state = %{clock_ms: 42, lot_allocation: []}
    batches = [batch("old", "fruit", 4), batch("other", "lumber", 2)]
    assert CargoLots.take(state, batches, 0, "fruit") == {state, [], batches}
  end

  test "whole lots keep identity, FIFO order and metadata without allocating" do
    state = %{clock_ms: 42, lot_allocation: []}
    unrelated = batch("other", "lumber", 9)
    first = batch("first", "fruit", 2)
    second = batch("second", "fruit", 3)
    last = batch("last", "fruit", 4)

    assert CargoLots.take(state, [unrelated, first, second, last], 5, "fruit") ==
             {state, [first, second], [unrelated, last]}
  end

  test "partial lots split into new children preserving cost and permanent parent identity" do
    state = %{clock_ms: 42, lot_allocation: ["taken", "remaining"]}
    original = batch("parent", "fruit", 5)
    {state, [taken], [remaining]} = CargoLots.take(state, [original], 2, "fruit")

    assert taken == %{original | "lot_id" => "taken", "quantity" => 2}
    assert remaining == %{original | "lot_id" => "remaining", "quantity" => 3}
    assert state.lot_allocation == []
    assert Enum.map(state.new_lots, & &1["parent_lot_id"]) == ["parent", "parent"]
    assert Enum.map(state.new_lots, & &1["quantity"]) == [2, 3]
    assert Enum.map(state.new_lots, & &1["expires_ms"]) == [100, 100]
  end

  test "conditioned splits retain origin expiry in lineage and current expiry in holdings" do
    original = Map.put(batch("parent", "fruit", 5), "freshness", %{"origin_expires_ms" => 75})
    {state, [taken], [remaining]} = CargoLots.take(%{clock_ms: 42}, [original], 2, "fruit")
    assert Enum.map(state.new_lots, & &1["expires_ms"]) == [75, 75]
    assert taken["expires_ms"] == 100
    assert remaining["expires_ms"] == 100
    assert taken["freshness"] == original["freshness"]
    assert remaining["freshness"] == original["freshness"]
  end

  test "batches without a good inherit the requested good when split" do
    original = Map.delete(batch("parent", "fruit", 5), "good")
    {state, [taken], [remaining]} = CargoLots.take(%{clock_ms: 42}, [original], 2, "fruit")
    assert taken["quantity"] + remaining["quantity"] == 5
    assert Enum.map(state.new_lots, & &1["good"]) == ["fruit", "fruit"]
  end

  test "insufficient matching stock fails instead of returning a partial fulfillment" do
    assert_raise MatchError, fn ->
      CargoLots.take(%{clock_ms: 42}, [batch("other", "lumber", 10)], 1, "fruit")
    end
  end

  defp batch(id, good, quantity),
    do: %{
      "lot_id" => id,
      "good" => good,
      "quantity" => quantity,
      "expires_ms" => 100,
      "unit_cost" => 123
    }
end
