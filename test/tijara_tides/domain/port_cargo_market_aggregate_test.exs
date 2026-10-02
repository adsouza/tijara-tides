defmodule TijaraTides.Domain.PortCargoMarketAggregateTest do
  use ExUnit.Case, async: true
  use ExUnitProperties
  alias TijaraTides.Domain.PortCargoMarket, as: Market
  alias TijaraTides.Domain.PortCargoMarket.Lots

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

  property "merchant supply preserves cargo promised to other buyers" do
    check all(
            stock <- integer(2..100),
            reserved <- integer(1..stock),
            max_runs: 50,
            max_shrinking_steps: 100
          ) do
      item = %{"id" => "lumber", "shelf_ms" => 0}
      {lots, batch} = Lots.create(%Lots{clock_ms: 0}, "lumber", stock, nil)
      market = %{supplier() | merchant: true, stock: stock, batches: [batch]}
      free = stock - reserved

      assert_raise ArgumentError, fn ->
        Market.supply(lots, market, free + 1, 20, item, 0, %{reserved_quantity: reserved})
      end

      if free > 0 do
        {_, remaining, cargo} =
          Market.supply(lots, market, free, 20, item, 0, %{reserved_quantity: reserved})

        assert Enum.sum(Enum.map(cargo, & &1.quantity)) == free
        assert remaining.stock == reserved
        assert Enum.sum(Enum.map(remaining.batches, & &1.quantity)) == reserved
      end
    end
  end

  test "one unit beyond an 80-unit merchant reservation is refused" do
    item = %{"id" => "lumber", "shelf_ms" => 0}
    {lots, batch} = Lots.create(%Lots{clock_ms: 0}, "lumber", 100, nil)
    market = %{supplier() | merchant: true, stock: 100, batches: [batch]}

    assert_raise ArgumentError, fn ->
      Market.supply(lots, market, 21, 20, item, 0, %{reserved_quantity: 80})
    end
  end

  test "supplier releases only available stock and records a permanent lot" do
    item = %{"id" => "lumber", "shelf_ms" => 0}
    state = %Lots{clock_ms: 0}
    {state, market, [cargo]} = Market.supply(state, supplier(), 10, 20, item)
    assert market.stock == 0
    assert market.budget == 300
    assert cargo.quantity == 10
    assert cargo.lot_id == hd(state.new_lots)["id"]
    assert_raise ArgumentError, fn -> Market.supply(state, market, 1, 20, item) end
  end

  test "buyer cannot exceed either demand or funds; consumer purchases do not become supply" do
    buyer = %{supplier() | seller: false, buyer: true, stock: 0, demand: 10, budget: 60}
    bought = Market.receive_cargo(buyer, 3, 20)
    assert {bought.demand, bought.budget, bought.stock} == {7, 0, 0}
    assert_raise ArgumentError, fn -> Market.receive_cargo(bought, 1, 20) end
    assert_raise ArgumentError, fn -> Market.receive_cargo(%{buyer | budget: 1000}, 11, 20) end

    cargo = [
      %TijaraTides.Domain.Ship.CargoBatch{
        good: buyer.good,
        quantity: 3,
        unit_cost: 20,
        lot_id: "existing",
        expires_ms: nil
      }
    ]

    assert Market.receive_cargo(%{buyer | merchant: true}, 3, 20, cargo).stock == 3
  end

  test "supplier quotes follow earliest expiry and minimum-life fills retain excluded lots" do
    item = %{"id" => "fruit", "shelf_ms" => 100_000, "reference_cents" => 20, "manual" => true}
    {lots, newer} = Lots.create(%Lots{clock_ms: 1000}, "fruit", 2, 5000)
    {lots, older} = Lots.create(lots, "fruit", 2, 3000)
    market = %{supplier("fruit") | stock: 4, batches: [newer, older]}
    quote = Market.quote(market, %{"goods" => %{"fruit" => item}, "ports" => %{}})
    assert Enum.map(quote["freshness_batches"], & &1.expires_ms) == [3000, 5000]
    {next, remaining, [cargo]} = Market.supply(lots, market, 1, 20, item, 2500)
    assert cargo.expires_ms == 5000
    assert cargo.quantity == 1
    assert cargo.unit_cost == 20
    assert remaining.stock == 3
    assert Enum.any?(remaining.batches, &(&1 == older))
    assert Enum.find(next.new_lots, &(&1["id"] == cargo.lot_id))["parent_lot_id"] == newer.lot_id
    assert_raise ArgumentError, fn -> Market.supply(lots, market, 3, 20, item, 2500) end
    assert_raise ArgumentError, fn -> Market.supply(lots, market, 1, 20, item, -1) end
  end

  test "expiry removes supplier stock before replenishment; partial lots preserve lineage" do
    item = %{"id" => "fruit", "shelf_ms" => 100_000, "reference_cents" => 20}
    {state, lot} = Lots.create(%Lots{clock_ms: 0}, "fruit", 10, 100_000)
    market = %{supplier("fruit") | batches: [lot]}
    {state, market, [part]} = Market.supply(state, market, 4, 20, item)
    assert market.stock == 6
    assert part.quantity == 4
    assert part.lot_id != lot.lot_id

    assert Enum.find(state.new_lots, &(&1["id"] == part.lot_id))["parent_lot_id"] ==
             lot.lot_id

    assert_raise ArgumentError, fn ->
      Market.supply(%{state | clock_ms: 100_000}, market, 1, 20, item)
    end

    {_, expired, _} = Market.replenish(%{state | clock_ms: 100_000}, market, item, 10_000, 1)
    assert {expired.stock, expired.batches} == {0, []}

    {_, replenished, _} =
      Market.replenish(%{state | clock_ms: 150_000}, expired, item, 10_000, 1)

    assert replenished.stock == 1
    assert hd(replenished.batches).expires_ms == 250_000
  end

  test "manufactured and merchant markets do not synthesize stock" do
    item = %{"id" => "appliances", "shelf_ms" => 0, "reference_cents" => 20}

    {_, factory, _} =
      Market.replenish(%Lots{clock_ms: 300_000}, supplier("appliances"), item, 10_000, 1)

    assert factory.stock == 10

    {_, merchant, _} =
      Market.replenish(
        %Lots{clock_ms: 300_000},
        %{supplier() | merchant: true},
        %{item | "id" => "lumber"},
        10_000,
        1
      )

    assert merchant.stock == 10
  end
end
