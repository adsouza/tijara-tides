defmodule TijaraTides.Infrastructure.GameQueriesTest do
  use ExUnit.Case, async: true
  alias TijaraTides.Infrastructure.{GameCatalogue, GameQueries}
  alias TijaraTides.UseCases.GameQueries, as: Queries

  test "manifest uses loaded catalogue names, weighted costs and earliest expiry" do
    cargo = [
      %{"good" => "lumber", "quantity" => 1, "unit_cost" => 200, "expires_ms" => nil},
      %{"good" => "fruit", "quantity" => 2, "unit_cost" => 100, "expires_ms" => 500},
      %{"good" => "fruit", "quantity" => 1, "unit_cost" => 400, "expires_ms" => 300}
    ]

    assert GameQueries.manifest(cargo) == [
             %{"good" => "fruit", "quantity" => 3, "average_cost" => 200.0, "expires_ms" => 300},
             %{"good" => "lumber", "quantity" => 1, "average_cost" => 200.0, "expires_ms" => nil}
           ]

    assert GameQueries.manifest([]) == []
  end

  test "purchase voyage supplies catalogue without changing quantity, fleet or clock" do
    {game, catalogue} = TijaraTides.CommandFuzzer.fixture()
    ship = game.entities["ships"]["company:1"]
    fleet = game.entities["ships"]
    item = catalogue["goods"]["lumber"]

    for quantity <- [1, 5], clock <- [0, 150_000] do
      expected =
        Queries.purchase_voyage(ship, item, quantity, "Singapore", fleet, clock, catalogue)

      assert GameQueries.purchase_voyage(ship, item, quantity, "Singapore", fleet, clock) ==
               expected

      assert is_map(expected)
    end

    assert catalogue == GameCatalogue.all()
  end

  test "trade adapter offers no owner trades in a public snapshot" do
    assert GameQueries.trade_limits(%{private: nil}, nil, "Singapore") == %{}
  end
end
