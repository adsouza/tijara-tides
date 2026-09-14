defmodule TijaraTides.UseCases.QueryFacadeTest do
  use ExUnit.Case, async: true

  alias TijaraTides.UseCases.{
    AuctionQueries,
    ExchangeQueries,
    GameQueries,
    MarketQueries,
    ShipPlanningQueries,
    WarehouseQueries
  }

  @focused [AuctionQueries, ExchangeQueries, MarketQueries, ShipPlanningQueries, WarehouseQueries]

  # Public only so ShipPlanningQueries can import it; not part of the read-side API.
  @internal [{:largest_trade, 3}]

  test "every focused query stays reachable through the exported facade" do
    Code.ensure_loaded!(GameQueries)
    exported = MapSet.new(GameQueries.__info__(:functions))

    missing =
      for module <- @focused,
          Code.ensure_loaded!(module),
          {name, arity} <- module.__info__(:functions),
          {name, arity} not in @internal,
          not MapSet.member?(exported, {name, arity}),
          do: "#{inspect(module)}.#{name}/#{arity}"

    assert missing == [],
           "GameQueries is missing a defdelegate for: #{Enum.join(missing, ", ")}"
  end
end
