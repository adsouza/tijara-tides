defmodule TijaraTides.Infrastructure.ShipHandlingMetadataTest do
  use ExUnit.Case, async: false
  @moduletag :game_database
  alias TijaraTides.SqlReplay, as: Sql
  alias TijaraTides.Infrastructure.{GameServer, GameCatalogue, Persistence.Repo}

  setup_all do
    Sql.repo()
  end

  test "handling volume and timeline survive replay and restart, stay private, and clear atomically" do
    Sql.with_world(fn c ->
      c = Sql.company(c)
      ship = c.company <> ":1"
      catalogue = GameCatalogue.all()
      volume = catalogue["goods"]["lumber"]["volume_l"]

      purchase = %{
        "action" => "buy",
        "ship" => ship,
        "good" => "lumber",
        "quantity" => 20,
        "limit" => 1_000_000,
        "destination" => "Singapore"
      }

      Sql.command(c, c.token, "load", purchase)
      loading = GameServer.snapshot(c.token, c.server)
      private = loading.private["ships"][ship]
      assert private["handling_started_ms"] == 0
      assert private["handling_volume_l"] == 20 * volume
      refute Map.has_key?(loading.public["ships"][ship], "handling_volume_l")
      refute Map.has_key?(loading.public["ships"][ship], "handling_started_ms")
      assert [[0, 20 * volume]] == metadata(c, ship)
      Sql.command(c, c.token, "load", purchase)
      assert GameServer.snapshot(c.token, c.server).private["ships"][ship] == private
      c = Sql.restart(c)
      assert GameServer.snapshot(c.token, c.server).private["ships"][ship] == private
      Sql.advance(c.server, 60_000)
      assert [[nil, nil]] == metadata(c, ship)

      Sql.command(c, c.token, "lease", %{
        "action" => "warehouse_lease",
        "port" => "Jakarta",
        "storage" => "dry",
        "blocks" => 5,
        "days" => 1,
        "price" => 500
      })

      warehouse =
        GameServer.snapshot(c.token, c.server).private["warehouses"] |> Map.keys() |> hd()

      Sql.command(c, c.token, "unload", %{
        "action" => "warehouse_transfer",
        "ship" => ship,
        "warehouse" => warehouse,
        "side" => "store",
        "good" => "lumber",
        "quantity" => 5
      })

      unloading = GameServer.snapshot(c.token, c.server).private["ships"][ship]
      assert unloading["handling_started_ms"] == 60_000
      assert unloading["handling_volume_l"] == 5 * volume
      assert Enum.sum(Enum.map(unloading["cargo"], & &1["quantity"])) == 15
      assert [[60_000, 5 * volume]] == metadata(c, ship)
      assert Sql.reload(c).entities["ships"][ship] == unloading
      Sql.advance(c.server, 60_000)
      assert [[nil, nil]] == metadata(c, ship)
      Sql.assert_rows(c, :sys.get_state(c.server).game)
    end)
  end

  defp metadata(c, ship) do
    Repo.query!(
      "SELECT handling_started_ms,handling_volume_l FROM game_ships WHERE world_id=$1 AND id=$2",
      [c.world, ship]
    ).rows
  end
end
