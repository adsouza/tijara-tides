defmodule TijaraTides.UseCases.LotAllocationTest do
  use ExUnit.Case, async: true
  alias TijaraTides.UseCases.LotAllocation
  alias TijaraTides.Domain.CargoLots

  defmodule Allocator do
    def allocate_lot_ids(owner, count) do
      send(owner, {:allocated, count})
      Enum.map(1..count, fn _ -> "lot:#{System.unique_integer([:positive])}" end)
    end
  end

  test "no allocation for no-op; exhausted pure operations rerun with unique IDs" do
    initial = %{clock_ms: 0}
    assert LotAllocation.run(initial, {Allocator, self()}, fn _ -> :unchanged end) == :unchanged
    refute_received {:allocated, _}

    result =
      LotAllocation.run(initial, {Allocator, self()}, fn state ->
        Enum.reduce(1..130, state, fn _, state ->
          {state, _} = CargoLots.create(state, "fruit", 1, nil)
          state
        end)
      end)

    ids = Enum.map(result.new_lots, & &1["id"])
    assert length(ids) == 130
    assert length(Enum.uniq(ids)) == 130
    assert_receive {:allocated, 64}
    assert_receive {:allocated, 64}
    assert_receive {:allocated, 128}
    refute_received {:allocated, _}
  end

  test "accepted operations retain unused IDs and reuse them without allocating" do
    game = %{clock_ms: 0, entities: %{}, revision: 0}
    create = fn state -> elem(CargoLots.create(state, "fruit", 1, nil), 0) end
    first = LotAllocation.run(game, {Allocator, self()}, create)
    assert_receive {:allocated, 64}
    accepted = TijaraTides.UseCases.CommitPreparation.accepted(first)
    assert length(accepted.lot_allocation) == 63
    second = LotAllocation.run(accepted, {Allocator, self()}, create)
    assert length(second.lot_allocation) == 62
    refute_received {:allocated, _}
    refute hd(first.new_lots)["id"] == hd(second.new_lots)["id"]
  end

  test "other domain errors propagate without allocation or retry" do
    assert_raise ArgumentError, "bad rule", fn ->
      LotAllocation.run(%{}, {Allocator, self()}, fn _ -> raise ArgumentError, "bad rule" end)
    end

    refute_received {:allocated, _}
  end
end
