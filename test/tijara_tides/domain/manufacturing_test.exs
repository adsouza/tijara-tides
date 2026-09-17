defmodule TijaraTides.Domain.ManufacturingTest do
  use ExUnit.Case, async: true
  alias TijaraTides.Domain.{Manufacturing, PortCargoMarket, PortCargoMarketWorld, State}

  test "production consumes exact inputs and funds and respects output capacity" do
    output = %PortCargoMarket{seller: true, merchant: false, stock: 498, budget: 1000}
    input = %PortCargoMarket{stock: 10, budget: 50}
    recipe = %{"inputs" => %{"crude_oil" => 2}, "local_cost_cents" => 10}

    {made, inputs} =
      Manufacturing.produce(output, %{"crude_oil" => input}, recipe, %{"crude_oil" => 100}, 100)

    assert made.stock == 500
    assert made.budget == 580
    assert inputs["crude_oil"].stock == 6
    assert inputs["crude_oil"].budget == 450
    assert {made, %{}} == Manufacturing.produce(made, inputs, recipe, %{"crude_oil" => 100}, 100)

    assert {%{output | budget: 209}, %{}} ==
             Manufacturing.produce(
               %{output | budget: 209},
               %{"crude_oil" => input},
               recipe,
               %{"crude_oil" => 100},
               1
             )

    assert {output, %{}} ==
             Manufacturing.produce(
               output,
               %{"crude_oil" => %{input | stock: 1}},
               recipe,
               %{"crude_oil" => 100},
               1
             )
  end

  test "factory inputs persist in local inventories, deliveries replenish them, and reload does not reseed" do
    cat = TijaraTides.Infrastructure.GameCatalogue.all()
    s = PortCargoMarketWorld.initialize(%{entities: %{}, clock_ms: 0, revision: 0}, cat)
    output = State.get(s, "markets", "Singapore|refined_fuel")
    input = State.get(s, "markets", "Singapore|crude_oil")
    assert input["feedstock"] and input["stock"] == 50
    s = State.put(s, "markets", "Singapore|refined_fuel", %{output | "stock" => 0})
    s = State.put(s, "markets", "Singapore|crude_oil", %{input | "stock" => 1})
    s = PortCargoMarketWorld.advance(%{s | clock_ms: 300_000}, cat)
    assert State.get(s, "markets", "Singapore|refined_fuel")["stock"] == 1
    assert State.get(s, "markets", "Singapore|crude_oil")["stock"] == 0
    s = PortCargoMarketWorld.initialize(s, cat)
    assert State.get(s, "markets", "Singapore|crude_oil")["stock"] == 0
    s = PortCargoMarketWorld.accept_cargo(s, "Singapore", "crude_oil", 2, 100)
    s = PortCargoMarketWorld.advance(%{s | clock_ms: 600_000}, cat)
    assert State.get(s, "markets", "Singapore|refined_fuel")["stock"] == 3
    assert State.get(s, "markets", "Singapore|crude_oil")["stock"] == 0
  end

  test "feedstock deliveries cannot overflow dedicated input storage" do
    market = %PortCargoMarket{
      buyer: true,
      merchant: false,
      feedstock: true,
      stock: 499,
      demand: 100,
      budget: 10000
    }

    assert_raise ArgumentError, fn -> PortCargoMarket.receive_cargo(market, 2, 1) end
    assert PortCargoMarket.receive_cargo(market, 1, 1).stock == 500
  end
end
