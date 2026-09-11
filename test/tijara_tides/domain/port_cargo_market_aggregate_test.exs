defmodule TijaraTides.Domain.PortCargoMarketAggregateTest do
  use ExUnit.Case, async: true
  alias TijaraTides.Domain.PortCargoMarket, as: Market

  defp supplier(good \\ "lumber") do
    %Market{
      port: "Jakarta",
      good: good,
      merchant: false,
      seller: true,
      buyer: false,
      stock: 10,
      demand: 0,
      budget: 100,
      batches: [],
      last_production: 0
    }
  end

  test "supplier releases only available stock and records a permanent lot" do
    item = %{"id" => "lumber", "shelf_ms" => 0}
    state = %{clock_ms: 0}
    {state, market, [cargo]} = Market.supply(state, supplier(), 10, 20, item)
    assert market.stock == 0
    assert market.budget == 300
    assert cargo["quantity"] == 10
    assert cargo["lot_id"] == hd(state.new_lots)["id"]
    assert_raise ArgumentError, fn -> Market.supply(state, market, 1, 20, item) end
  end

  test "buyer cannot exceed either demand or funds; consumer purchases do not become supply" do
    buyer = %{supplier() | seller: false, buyer: true, stock: 0, demand: 10, budget: 60}
    bought = Market.receive_cargo(buyer, 3, 20)
    assert {bought.demand, bought.budget, bought.stock} == {7, 0, 0}
    assert_raise ArgumentError, fn -> Market.receive_cargo(bought, 1, 20) end
    assert_raise ArgumentError, fn -> Market.receive_cargo(%{buyer | budget: 1000}, 11, 20) end
    assert Market.receive_cargo(%{buyer | merchant: true}, 3, 20).stock == 3
  end

  test "expiry removes supplier stock before replenishment; partial lots preserve lineage" do
    item = %{"id" => "fruit", "shelf_ms" => 100_000, "reference_cents" => 20}
    {state, lot} = TijaraTides.Domain.CargoLots.create(%{clock_ms: 0}, "fruit", 10, 100_000)
    market = %{supplier("fruit") | batches: [lot]}
    {state, market, [part]} = Market.supply(state, market, 4, 20, item)
    assert market.stock == 6
    assert part["quantity"] == 4
    assert part["lot_id"] != lot["lot_id"]

    assert Enum.find(state.new_lots, &(&1["id"] == part["lot_id"]))["parent_lot_id"] ==
             lot["lot_id"]

    assert_raise ArgumentError, fn ->
      Market.supply(%{state | clock_ms: 100_000}, market, 1, 20, item)
    end

    {_, expired} = Market.replenish(%{state | clock_ms: 100_000}, market, item)
    assert {expired.stock, expired.batches} == {0, []}
    {_, replenished} = Market.replenish(%{state | clock_ms: 150_000}, expired, item)
    assert replenished.stock == 1
    assert hd(replenished.batches)["expires_ms"] == 250_000
  end

  test "manufactured and merchant markets do not synthesize stock" do
    item = %{"id" => "appliances", "shelf_ms" => 0, "reference_cents" => 20}
    {_, factory} = Market.replenish(%{clock_ms: 300_000}, supplier("appliances"), item)
    assert factory.stock == 10

    {_, merchant} =
      Market.replenish(%{clock_ms: 300_000}, %{supplier() | merchant: true}, %{
        item
        | "id" => "lumber"
      })

    assert merchant.stock == 10
  end
end
