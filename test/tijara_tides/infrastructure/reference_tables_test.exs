defmodule TijaraTides.Infrastructure.ReferenceTablesTest do
  # Ships, instructions, routes and visits reference these tables by foreign key,
  # which is checked at commit, while every domain rule validates ids against the
  # catalogue. A catalogue port, good or hull class without its row here would
  # pause the world on first use, so adding one needs a migration that seeds it.
  use ExUnit.Case, async: false
  @moduletag :game_database
  alias TijaraTides.Domain.ShipClass
  alias TijaraTides.Infrastructure.GameCatalogue
  alias TijaraTides.Infrastructure.Persistence.Repo

  setup_all do
    TijaraTides.SqlReplay.repo()
  end

  test "every catalogue port, good and hull class has its reference row" do
    catalogue = GameCatalogue.all()

    for {table, ids} <- [
          {"game_ports", Map.keys(catalogue["ports"])},
          {"game_cargo_types", Map.keys(catalogue["goods"])},
          {"game_ship_classes", Map.keys(ShipClass.all())}
        ] do
      stored = MapSet.new(Repo.query!("SELECT id FROM #{table}").rows, &hd/1)
      assert ids != []
      assert Enum.reject(ids, &MapSet.member?(stored, &1)) == [], table
    end
  end
end
