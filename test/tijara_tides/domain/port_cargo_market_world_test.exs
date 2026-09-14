defmodule TijaraTides.Domain.PortCargoMarketWorldTest do
  use ExUnit.Case, async: true
  alias TijaraTides.Domain.{ChangeSet, PortCargoMarketWorld}
  alias TijaraTides.Domain.PortCargoMarket.Rows

  defp world(ids) do
    row = %{
      "port" => "p",
      "good" => "fruit",
      "merchant" => false,
      "seller" => true,
      "buyer" => false,
      "stock" => 10,
      "demand" => 0,
      "budget" => 100,
      "batches" => [%{"lot_id" => "parent", "quantity" => 10, "expires_ms" => 100}],
      "last_production" => 0
    }

    %{
      clock_ms: 0,
      entities: %{"markets" => %{"p|fruit" => row}},
      lot_allocation: ids,
      new_lots: [%{"id" => "earlier"}]
    }
  end

  test "adapter preserves row shape, allocation order, lineage and declared changes" do
    state = world(["part", "rest", "unused"])
    row = state.entities["markets"]["p|fruit"]
    assert row == Rows.encode(Rows.decode(row))

    {next, [cargo]} =
      PortCargoMarketWorld.release_stock(state, "p", "fruit", 4, 20, %{
        "id" => "fruit",
        "shelf_ms" => 100
      })

    assert cargo == %{
             "lot_id" => "part",
             "quantity" => 4,
             "expires_ms" => 100,
             "good" => "fruit",
             "unit_cost" => 20
           }

    assert next.lot_allocation == ["unused"]
    assert Enum.map(next.new_lots, & &1["id"]) == ["earlier", "part", "rest"]
    assert Enum.map(tl(next.new_lots), & &1["parent_lot_id"]) == ["parent", "parent"]

    assert next.entities["markets"]["p|fruit"]["batches"] ==
             [%{"lot_id" => "rest", "quantity" => 6, "expires_ms" => 100}]

    assert ChangeSet.since(state, next) == %{{"markets", "p|fruit"} => :put}
    assert :ok == ChangeSet.assert_complete!(state, next)
  end

  test "allocation exhaustion leaves the input available for an atomic retry" do
    state = world(["only-one"])

    assert_raise TijaraTides.Domain.LotIdsExhausted, fn ->
      PortCargoMarketWorld.release_stock(state, "p", "fruit", 4, 0, %{
        "id" => "fruit",
        "shelf_ms" => 100
      })
    end

    assert state.entities["markets"]["p|fruit"]["stock"] == 10
    assert state.new_lots == [%{"id" => "earlier"}]
  end

  test "whole-lot transfers allocate nothing and retain existing records" do
    state = world([])

    {next, [cargo]} =
      PortCargoMarketWorld.auction_supply(state, "p", "fruit", 10, 51, %{
        "id" => "fruit",
        "shelf_ms" => 100
      })

    assert cargo["lot_id"] == "parent"
    assert cargo["unit_cost"] == 0
    assert next.new_lots == state.new_lots
    assert next.lot_allocation == []
    assert next.entities["markets"]["p|fruit"]["budget"] == 151
  end

  test "a tick before expiry or production is an exact world no-op" do
    state = world([])

    catalogue = %{
      "goods" => %{"fruit" => %{"id" => "fruit", "shelf_ms" => 100, "reference_cents" => 20}}
    }

    assert PortCargoMarketWorld.advance(state, catalogue) == state
  end
end
