defmodule TijaraTides.Infrastructure.VoyagePiracyTest do
  use ExUnit.Case, async: false
  @moduletag :game_database
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  alias TijaraTides.Infrastructure.{GameServer, GameCatalogue}
  alias TijaraTides.Domain.Services.VoyageHazards
  alias TijaraTides.SqlReplay, as: Sql
  @endpoint TijaraTidesWeb.Endpoint

  setup_all do
    Sql.repo()
  end

  setup do
    previous = Application.get_env(:tijara_tides, :piracy)
    weather = Application.get_env(:tijara_tides, :weather)
    model = GameCatalogue.all()["piracy"]
    zones = Map.new(model["zones"], fn {id, z} -> {id, %{z | "chance_bps" => 10_000}} end)
    Application.put_env(:tijara_tides, :piracy, Map.put(model, "zones", zones))
    Application.put_env(:tijara_tides, :weather, %{"chance_bps" => 0})

    on_exit(fn ->
      Application.put_env(:tijara_tides, :piracy, previous)

      if weather,
        do: Application.put_env(:tijara_tides, :weather, weather),
        else: Application.delete_env(:tijara_tides, :weather)
    end)

    :ok
  end

  test "dispatch, incident and ledger persist atomically; restart and replay do not charge again; held UI is localized" do
    Sql.with_world(fn c ->
      {conn, token} = TijaraTides.WebFormFixture.session(c)

      {:ok, %{"company_id" => company}} =
        TijaraTides.CompanyFixture.command(
          token,
          "formation",
          %{
            "action" => "company",
            "name" => "Piracy test",
            "port" => "Tangier",
            "package" => "general"
          },
          c.server
        )

      ship_id = company <> ":1"

      payload = %{
        "action" => "sail",
        "ship" => ship_id,
        "destination" => "Athens",
        "fuel_limit" => 1_000_000
      }

      reply = Sql.command(c, token, "dispatch", payload)
      game = :sys.get_state(c.server).game
      ship = game.entities["ships"][ship_id]
      assert ship["piracy"]["pending"] != []
      Sql.assert_rows(c, game)
      first = hd(ship["piracy"]["pending"])
      at = ship["depart_ms"] + round(ship["weather"]["sailing_ms"] * first["attack_fraction"]) + 1
      elapsed = at - game.clock_ms
      catalogue = :sys.get_state(c.server).catalogue
      next = VoyageHazards.advance(%{game | clock_ms: at}, elapsed, catalogue, 600)
      Sql.persist(c, next)
      persisted = :sys.get_state(c.server).game
      incident = hd(persisted.entities["ships"][ship_id]["piracy"]["incidents"])
      assert incident["charge"] > 0
      Sql.assert_rows(c, persisted)

      count = fn ->
        TijaraTides.Infrastructure.Persistence.Repo.query!(
          "SELECT count(*) FROM game_journal_transactions WHERE world_id=$1 AND kind='piracy'",
          [c.world]
        ).rows
      end

      assert count.() == [[1]]
      c = Sql.restart(c)
      assert Sql.command(c, token, "dispatch", payload) == reply
      assert count.() == [[1]]
      Application.put_env(:tijara_tides, :game_server, c.server)
      restored = :sys.get_state(c.server).game

      assert restored.entities["ships"][ship_id]["piracy"] ==
               persisted.entities["ships"][ship_id]["piracy"]

      same = VoyageHazards.advance(restored, 0, catalogue, 600)
      assert Map.get(same, :journal, []) == []
      Sql.persist(c, same)
      assert count.() == [[1]]
      {:ok, view, _} = conn |> recycle() |> live("/play")
      render_click(view, "ship", %{"id" => ship_id})
      assert has_element?(view, ".piracy-wait", "Held by pirates")
      assert has_element?(view, ".piracy-wait .ui-emoji", "🏴‍☠️")
      assert has_element?(view, ".piracy-history", "Charge")
      assert has_element?(view, ".piracy-history", "Barbary Coast")
      {:ok, visitor, _} = build_conn() |> live("/play")
      render_click(visitor, "inspect-ship", %{"id" => ship_id})

      assert has_element?(
               visitor,
               "[id='public-ship-#{ship_id}'] .piracy-wait",
               "Held by pirates"
             )

      refute has_element?(visitor, ".piracy-history")

      Sql.command(c, token, "arabic", %{"action" => "locale", "locale" => "ar"})
      {:ok, view, _} = conn |> recycle() |> live("/play")
      render_click(view, "ship", %{"id" => ship_id})
      assert has_element?(view, ".piracy-wait", "محتجز لدى القراصنة")
      snapshot = GameServer.snapshot(nil, c.server).public["ships"][ship_id]
      refute Map.has_key?(snapshot, "piracy")
      refute Map.has_key?(GameServer.definitions().catalogue["piracy"], "salt")

      assert {:error, :held_by_pirates} =
               GameServer.command(
                 token,
                 "diversion",
                 %{
                   "action" => "reroute",
                   "ship" => ship_id,
                   "destination" => "Dubai",
                   "fuel_limit" => 1_000_000
                 },
                 c.server
               )
    end)
  end
end
