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

  test "route protection and waiting choice survive SQL, replay and automatic departure" do
    Sql.with_world(fn c ->
      {conn, token} = TijaraTides.WebFormFixture.session(c)

      {:ok, %{"company_id" => company}} =
        TijaraTides.CompanyFixture.command(
          token,
          "auto-formation",
          %{
            "action" => "company",
            "name" => "Auto protected",
            "port" => "Tangier",
            "package" => "general"
          },
          c.server
        )

      ship_id = company <> ":1"

      route = fn operation, values ->
        Map.merge(%{"action" => "route", "ship" => ship_id, "operation" => operation}, values)
      end

      Sql.command(c, token, "auto-first", route.("add_stop", %{"port" => "Tangier"}))
      Sql.command(c, token, "auto-next", route.("add_stop", %{"port" => "Athens"}))
      {:ok, view, _} = conn |> recycle() |> live("/play")
      render_click(view, "ship", %{"id" => ship_id})
      assert has_element?(view, "[id='route-protection-#{ship_id}'] option[value=none][selected]")

      render_submit(element(view, "[id='route-protection-#{ship_id}']"), %{
        "protection" => "both",
        "request_id" => "auto-protection"
      })

      assert :sys.get_state(c.server).game.entities["ship_routes"][ship_id]["protection"] ==
               "both"

      Sql.command(c, token, "auto-start", route.("start", %{"auto_depart" => true}))
      s = :sys.get_state(c.server).game
      cat = :sys.get_state(c.server).catalogue
      co = s.entities["companies"][company]

      s =
        TijaraTides.Domain.CompanyFinanceWorld.post(s, company, "test_funds", [
          {"cash_available", -co["cash"] + co["reserved"]},
          {"capital", co["cash"] - co["reserved"]}
        ])

      s =
        s
        |> TijaraTides.Domain.ShipWorld.prepare_visits(cat)
        |> TijaraTides.Domain.Services.DepartureFunding.advance(cat)

      waiting = s.entities["departure_requests"][ship_id]
      assert waiting["protection"] == "both"
      Sql.persist(c, s)
      # The saved request retains both while the route's next request uses none.
      payload = route.("set_protection", %{"protection" => "none"})
      Sql.command(c, token, "auto-next-choice", payload)
      s = :sys.get_state(c.server).game
      assert s.entities["departure_requests"][ship_id]["protection"] == "both"
      restored = Sql.assert_rows(c, s)
      assert restored.entities["ship_routes"][ship_id]["protection"] == "none"
      GenServer.stop(view.pid, :normal)
      c = Sql.restart(c)
      Application.put_env(:tijara_tides, :game_server, c.server)
      before = :sys.get_state(c.server).game
      Sql.command(c, token, "auto-next-choice", payload)
      assert :sys.get_state(c.server).game.revision == before.revision
      assert before.entities["departure_requests"][ship_id] == waiting
      {:ok, view, _} = conn |> recycle() |> live("/play")
      render_click(view, "ship", %{"id" => ship_id})
      assert has_element?(view, "[id='route-protection-#{ship_id}'] option[value=none][selected]")

      assert has_element?(
               view,
               "[id='route-request-protection-#{ship_id}']",
               "Guards and insurance"
             )

      GenServer.stop(view.pid, :normal)
      conn = conn |> recycle() |> post("/locale", %{"locale" => "ar", "return_to" => "/play"})
      {:ok, view, _} = conn |> recycle() |> live("/play")
      render_click(view, "ship", %{"id" => ship_id})
      assert has_element?(view, "[id='route-protection-#{ship_id}']", "حفظ الحماية")
      assert has_element?(view, "[id='route-request-protection-#{ship_id}']", "الحراس والتأمين")
      s = :sys.get_state(c.server).game
      n = waiting["required"] + 10_000

      s =
        TijaraTides.Domain.CompanyFinanceWorld.post(s, company, "test_funds", [
          {"cash_available", n},
          {"capital", -n}
        ])

      Sql.persist(c, s)
      Sql.advance(c.server, 1)
      next = :sys.get_state(c.server).game
      ship = next.entities["ships"][ship_id]
      assert ship["status"] == "sailing"
      assert ship["piracy"]["protection"] == "both"
      assert next.entities["departure_requests"][ship_id] == nil
      assert next.entities["ship_routes"][ship_id]["protection"] == "none"

      entries =
        TijaraTides.Infrastructure.Persistence.Repo.query!(
          "SELECT e.account_code,e.amount_cents FROM game_journal_entries e JOIN game_journal_transactions t ON t.id=e.transaction_id WHERE t.world_id=$1 AND t.kind='departure' AND t.sealed",
          [c.world]
        ).rows

      assert Enum.any?(entries, fn [account, amount] ->
               account == "piracy_guard_expense" && amount > 0
             end)

      assert Enum.any?(entries, fn [account, amount] ->
               account == "piracy_premium_expense" && amount > 0
             end)

      Sql.assert_rows(c, next)
      GenServer.stop(view.pid, :normal)
      c = Sql.restart(c)
      assert :sys.get_state(c.server).game.entities["ships"][ship_id]["piracy"] == ship["piracy"]
    end)
  end

  test "protection toggles quote and pay once, survive restart, and reimburse insured attacks" do
    model = GameCatalogue.all()["piracy"]
    # Force an insured incident without making the guard fee free.
    zones = Map.new(model["zones"], fn {id, z} -> {id, %{z | "guard_pct" => 0}} end)
    Application.put_env(:tijara_tides, :piracy, Map.put(model, "zones", zones))

    Sql.with_world(fn c ->
      {conn, token} = TijaraTides.WebFormFixture.session(c)

      {:ok, %{"company_id" => company}} =
        TijaraTides.CompanyFixture.command(
          token,
          "formation",
          %{
            "action" => "company",
            "name" => "Protected",
            "port" => "Tangier",
            "package" => "general"
          },
          c.server
        )

      id = company <> ":1"
      {:ok, view, _} = conn |> recycle() |> live("/play")
      render_click(view, "ship", %{"id" => id})
      render_click(view, "preview", %{"destination" => "Valencia"})
      refute has_element?(view, "#voyage-insurance")
      render_click(view, "preview", %{"destination" => "Athens"})
      assert has_element?(view, "#voyage-protection", "Barbary Coast")
      assert has_element?(view, "#voyage-guards[aria-checked=false]")
      render_click(view, "voyage-protection", %{"kind" => "guards"})
      render_click(view, "voyage-protection", %{"kind" => "insurance"})
      assert has_element?(view, "#voyage-guards[aria-checked=true]")
      assert has_element?(view, "#voyage-insurance[aria-checked=true]")
      offered = GameServer.preview(token, id, "Athens", c.server)
      terms = offered["protection_options"]["both"]
      before = :sys.get_state(c.server).game
      render_click(view, "sail", %{"request_id" => "protected-dispatch"})
      next = :sys.get_state(c.server).game
      assert next.revision == before.revision + 1
      ship = next.entities["ships"][id]
      assert ship["piracy"]["protection"] == "both"

      delta =
        before.entities["companies"][company]["cash"] -
          next.entities["companies"][company]["cash"]

      assert delta == offered["canal_fees"] + terms["cost"]
      assert has_element?(view, ".voyage-protection", "Armed guards and voyage insurance")

      entries =
        TijaraTides.Infrastructure.Persistence.Repo.query!(
          "SELECT e.account_code,e.amount_cents FROM game_journal_entries e JOIN game_journal_transactions t ON t.id=e.transaction_id WHERE t.world_id=$1 AND t.kind='departure' AND t.sealed",
          [c.world]
        ).rows
        |> Enum.map(fn [code, amount] -> {code, amount} end)

      assert Enum.sum(for {"piracy_guard_expense", n} <- entries, do: n) == terms["guard_fee"]
      assert Enum.sum(for {"piracy_premium_expense", n} <- entries, do: n) == terms["premium"]
      Sql.assert_rows(c, next)
      GenServer.stop(view.pid, :normal)
      c = Sql.restart(c)

      payload = %{
        "action" => "sail",
        "ship" => id,
        "destination" => "Athens",
        "fuel_limit" => offered["fuel"],
        "protection" => "both",
        "protection_limit" => terms["cost"]
      }

      assert {:ok, _} = GameServer.command(token, "protected-dispatch", payload, c.server)
      assert :sys.get_state(c.server).game.revision == next.revision
      game = :sys.get_state(c.server).game
      crossing = hd(game.entities["ships"][id]["piracy"]["pending"])

      at =
        TijaraTides.Domain.Weather.time_at(
          ship["weather"],
          ship["depart_ms"],
          crossing["attack_fraction"]
        ) + 1

      cat = :sys.get_state(c.server).catalogue
      hit = VoyageHazards.advance(%{game | clock_ms: at}, at - game.clock_ms, cat, 600)
      incident = hd(hit.entities["ships"][id]["piracy"]["incidents"])
      assert incident["recovery"] == div(incident["charge"] * 80, 100)
      assert incident["recovery"] > 0

      assert hit.entities["companies"][company]["reserved"] ==
               game.entities["companies"][company]["reserved"]

      Sql.persist(c, hit)
      c = Sql.restart(c)
      persisted = :sys.get_state(c.server).game

      assert hd(persisted.entities["ships"][id]["piracy"]["incidents"])["recovery"] ==
               incident["recovery"]

      assert Map.get(VoyageHazards.advance(persisted, 0, cat, 600), :journal, []) == []
      Sql.assert_rows(c, persisted)
    end)
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
