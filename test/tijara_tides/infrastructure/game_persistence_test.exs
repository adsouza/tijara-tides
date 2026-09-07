defmodule TijaraTides.Infrastructure.GamePersistenceTest do
  use ExUnit.Case, async: false
  @moduletag :game_database
  alias TijaraTides.Infrastructure.GameServer
  alias TijaraTides.Infrastructure.Persistence.{GameStore, Repo}
  alias TijaraTides.Domain.Game
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  @endpoint TijaraTidesWeb.Endpoint

  setup_all do
    port = System.fetch_env!("TIJARA_TEST_DB_PORT") |> String.to_integer()

    start_supervised!(
      {Repo,
       hostname: "127.0.0.1",
       port: port,
       username: "postgres",
       database: "postgres",
       ssl: false,
       pool_size: 4}
    )

    Ecto.Migrator.run(Repo, Application.app_dir(:tijara_tides, "priv/repo/migrations"), :up,
      all: true,
      log: false
    )

    :ok
  end

  setup do
    id = Ecto.UUID.generate()

    server =
      start_supervised!({GameServer, name: nil, enabled: true, world_id: id, tick_ms: 86_400_000})

    {:ok, code} = GameServer.seed(server)
    %{server: server, code: code, world_id: id}
  end

  test "concurrent redemption creates one account and one session", %{
    server: server,
    code: code,
    world_id: world
  } do
    results =
      1..8
      |> Task.async_stream(fn _ -> GameServer.redeem(code, server) end, max_concurrency: 8)
      |> Enum.map(fn {:ok, r} -> r end)

    assert Enum.count(results, &match?({:ok, _}, &1)) == 1

    assert [[1]] =
             Repo.query!(
               "SELECT count(*) FROM game_accounts WHERE world_id=$1",
               [world]
             ).rows

    assert [[1]] =
             Repo.query!(
               "SELECT count(*) FROM game_sessions WHERE world_id=$1",
               [world]
             ).rows
  end

  test "authenticated reconnect repairs a missing world timer without duplicate ticks", %{
    server: server,
    code: code
  } do
    {:ok, %{"session" => token}} = GameServer.redeem(code, server)
    :ok = GameServer.connect(token, server)
    original = :sys.get_state(server).timer
    Process.cancel_timer(original)
    :ok = GameServer.connect(token, server)
    repaired = :sys.get_state(server).timer
    assert repaired != original
    assert is_integer(Process.read_timer(repaired))
    :ok = GameServer.connect(token, server)
    assert :sys.get_state(server).timer == repaired

    before = GameServer.snapshot(token, server)
    send(server, {:timeout, original, :tick})
    assert GameServer.snapshot(token, server) == before
    send(server, {:timeout, repaired, :tick})
    assert GameServer.snapshot(token, server).public["revision"] > before.public["revision"]
    assert :sys.get_state(server).timer != repaired
  end

  test "command retries grant one fleet, preserve balances, and reject request conflicts", %{
    server: server,
    code: code
  } do
    {:ok, %{"session" => token}} = GameServer.redeem(code, server)

    command = %{
      "action" => "company",
      "name" => "Durable Shipping",
      "port" => "Jakarta",
      "package" => "general"
    }

    request = GameServer.request_id()
    assert {:ok, result} = GameServer.command(token, request, command, server)
    before = GameServer.snapshot(token, server)
    assert {:ok, ^result} = GameServer.command(token, request, command, server)
    assert GameServer.snapshot(token, server) == before
    assert map_size(before.private["ships"]) == 3

    assert {:error, :request_conflict} =
             GameServer.command(token, request, %{command | "name" => "Different"}, server)
  end

  test "invitation retry returns the same usable code and revocation removes access", %{
    server: server,
    code: code
  } do
    {:ok, %{"session" => token}} = GameServer.redeem(code, server)
    request = GameServer.request_id()
    assert {:ok, result} = GameServer.command(token, request, %{"action" => "invite"}, server)
    assert {:ok, ^result} = GameServer.command(token, request, %{"action" => "invite"}, server)
    assert {:ok, _} = GameServer.redeem(result["code"], server)
    assert GameServer.snapshot(token, server).private["account"]["invite_quota"] == 2
    GameServer.sign_out(token, server)
    assert GameServer.snapshot(token, server).private == nil

    assert {:error, :invalid_session} =
             GameServer.command(token, "after-signout", %{"action" => "invite"}, server)
  end

  test "restart restores ownership and state without offline catch-up; old owner is fenced", %{
    server: server,
    code: code,
    world_id: world
  } do
    {:ok, %{"session" => token}} = GameServer.redeem(code, server)

    {:ok, _} =
      GameServer.command(
        token,
        "company",
        %{
          "action" => "company",
          "name" => "Restored",
          "port" => "Jakarta",
          "package" => "general"
        },
        server
      )

    before = GameServer.snapshot(token, server)

    new =
      start_supervised!({GameServer, name: nil, enabled: true, world_id: world}, id: :new_owner)

    assert GameServer.snapshot(token, new) == before

    assert {:error, :ownership_lost} =
             GameServer.command(token, "invite", %{"action" => "invite"}, server)

    assert GameServer.snapshot(token, server).status == :unavailable
    assert GameServer.snapshot(token, new) == before
  end

  test "failed transaction rolls back changed entities and receipt together", %{world_id: world} do
    {:ok, before} = GameStore.claim(Repo, world)
    {:ok, changed, _} = Game.seed_invite(before, "rollback-probe")

    assert_raise Postgrex.Error, fn ->
      GameStore.commit(
        Repo,
        world,
        before.epoch,
        before,
        changed,
        {"account", "request", nil, %{}}
      )
    end

    assert [] ==
             Repo.query!(
               "SELECT id FROM game_invitations WHERE world_id=$1 AND id='rollback-probe'",
               [
                 world
               ]
             ).rows

    assert [] ==
             Repo.query!("SELECT request_id FROM game_receipts WHERE world_id=$1", [world]).rows
  end

  test "browser can redeem, form a company, buy, sail, sell and reconnect", %{
    server: server,
    code: code
  } do
    Application.put_env(:tijara_tides, :game_server, server)
    on_exit(fn -> Application.delete_env(:tijara_tides, :game_server) end)
    conn = build_conn() |> post("/session/redeem", %{"code" => code})
    assert redirected_to(conn) == "/play"
    token = Plug.Conn.get_session(conn, :account_token)
    assert is_binary(token)
    {:ok, view, _} = conn |> recycle() |> live("/play")

    view
    |> form("#company-form", %{
      "name" => "Browser Shipping",
      "port" => "Jakarta",
      "package" => "general"
    })
    |> render_change()

    assert has_element?(view, "#port-selector option[selected]", "Jakarta")
    assert has_element?(view, "#company-form input[name=name][value='Browser Shipping']")

    view
    |> form("form[phx-submit=company]", %{
      "name" => "Browser Shipping",
      "port" => "Jakarta",
      "package" => "general"
    })
    |> render_submit()

    assert render(view) =~ "Browser Shipping"
    view |> form("#cargo-market-selector", %{"good" => "Scrap aluminium"}) |> render_change()
    assert has_element?(view, "#market-good option[selected]", "Aluminium scrap")
    assert has_element?(view, "#cargo-supply th[aria-sort=ascending]", "Buy price")
    assert has_element?(view, "#cargo-markets tr[data-port='Singapore'] td", "500")
    assert has_element?(view, "#cargo-supply tr[data-port='Singapore']")
    refute has_element?(view, "#cargo-demand tr[data-port='Singapore']")
    assert has_element?(view, "#cargo-demand th[aria-sort=descending]", "Sell price")
    view |> element("#cargo-markets button[phx-value-column=stock]") |> render_click()
    send(view.pid, {:game_changed, 0})
    assert has_element?(view, "#market-good option[selected]", "Aluminium scrap")
    assert has_element?(view, "#cargo-supply th[aria-sort=ascending]", "Supply")
    view |> element("#cargo-markets button[phx-value-id='Singapore']") |> render_click()
    assert has_element?(view, "#port-selector option[selected]", "Singapore")
    view |> form("#cargo-market-selector", %{"good" => "Lumber"}) |> render_change()

    snapshot = GameServer.snapshot(token, server)
    ship = snapshot.private["ships"] |> Map.values() |> Enum.sort_by(& &1["id"]) |> hd()
    other_ship = snapshot.private["ships"] |> Map.values() |> Enum.find(&(&1["id"] != ship["id"]))
    render_click(view, "ship", %{"id" => other_ship["id"]})

    refute has_element?(view, "#world-map [phx-click=inspect-ship][phx-value-id='#{ship["id"]}']")

    view
    |> element("#port-traffic [phx-click=inspect-ship][phx-value-id='#{ship["id"]}']")
    |> render_click()

    assert has_element?(
             view,
             "button[phx-click=ship][phx-value-id='#{ship["id"]}'][aria-pressed=true]"
           )

    assert has_element?(
             view,
             "button[phx-click=ship][phx-value-id='#{other_ship["id"]}'][aria-pressed=false]"
           )

    assert has_element?(view, "h3", "#{ship["name"]} — private manifest")
    refute has_element?(view, "#public-ship-inspector")

    render_click(view, "map-region", %{"id" => "Pearl River Delta"})
    assert has_element?(view, "#region-ports button", "Guangzhou")
    assert has_element?(view, "#region-ports button", "Hong Kong")
    assert has_element?(view, "#region-ports button", "Shenzhen")
    refute has_element?(view, "#world-map[viewBox='0 0 1000 500']")
    render_click(view, "port", %{"id" => "Hong Kong"})
    assert has_element?(view, "#port-selector option[selected]", "Hong Kong")
    assert has_element?(view, "#region-ports button[aria-pressed=true]", "Hong Kong")
    send(view.pid, {:game_changed, 0})
    assert has_element?(view, "#region-ports", "Pearl River Delta")
    render_click(view, "map-world")
    refute has_element?(view, "#region-ports")
    assert has_element?(view, "#world-map[viewBox='0 0 1000 500']")
    render_change(view, "port", %{"id" => "Tokyo"})
    assert has_element?(view, "th", "Buy / supply")
    refute has_element?(view, "th", "Aboard")
    refute has_element?(view, "th", "Trade")
    refute has_element?(view, "[id^=aboard-]")
    render_change(view, "port", %{"id" => "Jakarta"})
    assert has_element?(view, "th", "Aboard")
    assert has_element?(view, "th", "Trade")
    refute has_element?(view, "td", "Appliances")
    refute has_element?(view, "td", "Fruit")
    assert has_element?(view, "td", "Lumber")
    assert has_element?(view, "#aboard-Lumber", "0")
    assert has_element?(view, "#trade-buy-Lumber .purchase-total", "$227.00 total")

    render_change(view, "trade-preview", %{
      "action" => "buy",
      "good" => "Lumber",
      "quantity" => "500"
    })

    assert has_element?(
             view,
             "#trade-buy-Lumber .purchase-total.text-red-400",
             "$113500.00 total"
           )

    render_change(view, "trade-preview", %{
      "action" => "buy",
      "good" => "Lumber",
      "quantity" => "10"
    })

    assert has_element?(view, "#trade-buy-Lumber .purchase-total", "$2270.00 total")
    refute has_element?(view, "#trade-buy-Lumber .purchase-total.text-red-400")

    assert render(view) =~ "900 m³"
    assert render(view) =~ "1.6 m³"

    render_submit(view, "trade", %{
      "action" => "buy",
      "good" => "Lumber",
      "quantity" => "10",
      "limit" => "30000"
    })

    assert GameServer.snapshot(token, server).private["ships"][ship["id"]]["status"] == "loading"
    assert has_element?(view, "#aboard-Lumber", "10")
    assert render(view) =~ "16 m³"
    refute has_element?(view, "td", "Appliances")
    advance(server, 6000)
    refute has_element?(view, "td", "Appliances")

    render_submit(view, "trade", %{
      "action" => "buy",
      "good" => "Lumber",
      "quantity" => "1",
      "limit" => "30000"
    })

    assert has_element?(view, "#manifest-Lumber td", "11")
    assert has_element?(view, "#manifest-Lumber", "17.6 m³")
    assert has_element?(view, "#ship-capacity", "5500 / 500000 kg")
    assert has_element?(view, "#ship-capacity", "17.6 m³ / 900 m³")
    assert has_element?(view, "#manifest-Lumber td", "$225.00")

    view
    |> element("button[phx-click=sort-manifest][phx-value-column=quantity]")
    |> render_click()

    assert has_element?(view, "th[aria-sort=ascending]", "Lots")

    view
    |> element("button[phx-click=sort-manifest][phx-value-column=quantity]")
    |> render_click()

    send(view.pid, {:game_changed, 0})
    assert has_element?(view, "th[aria-sort=descending]", "Lots")

    assert length(GameServer.snapshot(token, server).private["ships"][ship["id"]]["cargo"]) == 2
    advance(server, 2000)
    render_submit(view, "preview", %{"destination" => "Singapore"})
    assert render(view) =~ "Reserve fuel and sail"
    estimate = GameServer.preview(token, ship["id"], "Singapore", server)
    render_click(view, "sail")
    assert GameServer.snapshot(token, server).private["ships"][ship["id"]]["status"] == "sailing"
    render_click(view, "ship", %{"id" => other_ship["id"]})

    view
    |> element("#world-map [phx-click=inspect-ship][phx-value-id='#{ship["id"]}']")
    |> render_click()

    assert has_element?(
             view,
             "button[phx-click=ship][phx-value-id='#{ship["id"]}'][aria-pressed=true]"
           )

    advance(server, estimate["duration_ms"] + 1000)

    render_submit(view, "trade", %{
      "action" => "sell",
      "good" => "Lumber",
      "quantity" => "11",
      "limit" => "1"
    })

    render_change(view, "port", %{"id" => "Singapore"})
    refute has_element?(view, "td", "Appliances")
    after_sale = GameServer.snapshot(token, server)
    assert after_sale.private["ships"][ship["id"]]["cargo"] == []
    {:ok, spectator, _} = build_conn() |> live("/play")
    render_click(spectator, "inspect-ship", %{"id" => ship["id"]})
    assert has_element?(spectator, "#public-ship-inspector", "Company: Browser Shipping")
    assert has_element?(spectator, "#public-ship-inspector", "Class: Balanced freighter")
    refute render(spectator) =~ "private manifest"
    refute has_element?(spectator, "table[aria-label='Ship cargo manifest']")
    GenServer.stop(spectator.pid)
    GenServer.stop(view.pid)
    {:ok, reconnected, _} = conn |> recycle() |> live("/play")
    assert render(reconnected) =~ "Browser Shipping"
    refute render(reconnected) =~ token
  end

  test "perishable disclosures follow quantity, dispatch and underway time", %{
    server: server,
    code: code
  } do
    Application.put_env(:tijara_tides, :game_server, server)
    on_exit(fn -> Application.delete_env(:tijara_tides, :game_server) end)
    conn = build_conn() |> post("/session/redeem", %{"code" => code})
    token = Plug.Conn.get_session(conn, :account_token)
    {:ok, view, _} = conn |> recycle() |> live("/play")

    view
    |> form("#company-form", %{
      "name" => "Cold Shipping",
      "port" => "Jakarta",
      "package" => "fresh"
    })
    |> render_submit()

    view |> form("#trade-buy-Fruit", %{"quantity" => "20"}) |> render_change()
    assert has_element?(view, "#trade-buy-Fruit", "20 lots: first expiry")
    assert has_element?(view, "#trade-buy-Fruit", "0.2 min handling")
    assert has_element?(view, "#trade-buy-Fruit", "Estimates may change")
    view |> form("#trade-buy-Fruit", %{"quantity" => "20"}) |> render_submit()
    advance(server, 11_000)
    view |> form("#voyage-preview", %{"destination" => "Singapore"}) |> render_submit()
    assert has_element?(view, ".voyage-freshness", "Fruit: estimated time to first expiry")
    assert has_element?(view, ".voyage-freshness", "after unloading")
    render_click(view, "sail")
    before = GameServer.snapshot(token, server).private["voyage_freshness"]
    advance(server, 60_000)
    assert has_element?(view, ".voyage-freshness", "Fruit: estimated time to first expiry")
    # As the ship advances normally, the absolute arrival and unloading times stay
    # fixed; remaining freshness at those future instants is therefore unchanged.
    assert GameServer.snapshot(token, server).private["voyage_freshness"] == before
  end

  test "perishable lots split permanently and journal retries and failures stay atomic", %{
    server: server,
    code: code,
    world_id: world
  } do
    alias TijaraTides.Infrastructure.Persistence.FinancialLedger
    {:ok, %{"session" => token}} = GameServer.redeem(code, server)
    :ok = GameServer.connect(token, server)

    {:ok, _} =
      GameServer.command(
        token,
        "starter",
        %{
          "action" => "company",
          "name" => "Ledger company",
          "port" => "Jakarta",
          "package" => "fresh"
        },
        server
      )

    snapshot = GameServer.snapshot(token, server)
    ship = snapshot.private["ships"] |> Map.values() |> Enum.find(&(&1["class"] == "reefer"))

    [[parent]] =
      Repo.query!(
        "SELECT lot_id FROM game_cargo_holdings WHERE world_id=$1 AND market_id='Jakarta|Fruit' ORDER BY position LIMIT 1",
        [world]
      ).rows

    buy = %{
      "action" => "buy",
      "ship" => ship["id"],
      "good" => "Fruit",
      "quantity" => 2,
      "limit" => 100_000
    }

    {:ok, result} = GameServer.command(token, "buy", buy, server)
    assert {:ok, ^result} = GameServer.command(token, "buy", buy, server)

    [[1]] =
      Repo.query!(
        "SELECT count(*) FROM game_journal_transactions WHERE world_id=$1 AND request_id='buy'",
        [world]
      ).rows

    assert [[500, 2]] ==
             Repo.query!(
               "SELECT sum(original_quantity_lots)::bigint,count(*) FROM game_cargo_lots WHERE world_id=$1 AND parent_lot_id=$2",
               [world, parent]
             ).rows

    assert [[0]] ==
             Repo.query!(
               "SELECT count(*) FROM game_cargo_holdings WHERE world_id=$1 AND lot_id=$2",
               [world, parent]
             ).rows

    [cargo] = GameServer.snapshot(token, server).private["ships"][ship["id"]]["cargo"]
    refute cargo["lot_id"] == parent

    assert [[parent]] ==
             Repo.query!(
               "SELECT parent_lot_id FROM game_cargo_lots WHERE world_id=$1 AND id=$2",
               [world, cargo["lot_id"]]
             ).rows

    assert :ok == FinancialLedger.audit(Repo, world)

    [[tx]] =
      Repo.query!(
        "SELECT id FROM game_journal_transactions WHERE world_id=$1 AND request_id='buy'",
        [world]
      ).rows

    assert_raise Postgrex.Error, fn ->
      Repo.query!("UPDATE game_journal_entries SET amount_cents=1 WHERE transaction_id=$1", [tx])
    end

    assert_raise Postgrex.Error, fn ->
      Repo.query!("DELETE FROM game_journal_transactions WHERE id=$1", [tx])
    end

    assert_raise Postgrex.Error, fn ->
      Repo.query!("INSERT INTO game_journal_entries VALUES($1,99,'capital',1)", [tx])
    end

    assert_raise Postgrex.Error, fn ->
      Repo.query!(
        "SELECT post_game_journal($1,$2,'bad',0,0,NULL,NULL,NULL,ARRAY['cash_available','capital'],ARRAY[10,-9]::bigint[])",
        [world, ship["company_id"]]
      )
    end

    assert :ok == FinancialLedger.audit(Repo, world)

    advance(server, 2000)
    {:ok, before} = GameStore.claim(Repo, world)

    other =
      before.entities["ships"]
      |> Map.values()
      |> Enum.find(&(&1["company_id"] == ship["company_id"] and &1["id"] != ship["id"]))

    moved =
      before
      |> put_in([:entities, "ships", ship["id"], "cargo"], [])
      |> put_in([:entities, "ships", other["id"], "cargo"], [cargo])

    assert {:ok, :ok} = GameStore.commit(Repo, world, before.epoch, before, moved)

    assert [[other["id"]]] ==
             Repo.query!(
               "SELECT ship_id FROM game_cargo_holdings WHERE world_id=$1 AND lot_id=$2",
               [world, cargo["lot_id"]]
             ).rows

    before = moved

    account =
      Game.get(before, "accounts", snapshot.private["account"]["id"])

    {:ok, changed, _} =
      Game.execute(before, account, buy, %{}, TijaraTides.Infrastructure.GameCatalogue.all())

    [[lot_count]] =
      Repo.query!("SELECT count(*) FROM game_cargo_lots WHERE world_id=$1", [world]).rows

    [[journal_count]] =
      Repo.query!("SELECT count(*) FROM game_journal_transactions WHERE world_id=$1", [world]).rows

    assert_raise Postgrex.Error, fn ->
      GameStore.commit(
        Repo,
        world,
        before.epoch,
        before,
        changed,
        {account["id"], "rollback", nil, %{}}
      )
    end

    assert [[lot_count]] ==
             Repo.query!("SELECT count(*) FROM game_cargo_lots WHERE world_id=$1", [world]).rows

    assert [[journal_count]] ==
             Repo.query!("SELECT count(*) FROM game_journal_transactions WHERE world_id=$1", [
               world
             ]).rows

    assert :ok == FinancialLedger.audit(Repo, world)
    {:ok, restored} = GameStore.claim(Repo, world)
    assert restored.entities == before.entities
    assert restored.next_lot_id == before.next_lot_id

    assert_raise Postgrex.Error, fn ->
      Repo.query!("UPDATE game_ledger_balances SET balance_cents=0 WHERE world_id=$1", [world])
    end

    assert_raise Postgrex.Error, fn ->
      Repo.query!(
        "UPDATE game_cargo_lots SET original_quantity_lots=1 WHERE world_id=$1 AND id=$2",
        [world, cargo["lot_id"]]
      )
    end

    unsupported =
      update_in(restored, [:entities, "companies", ship["company_id"], "cash"], &(&1 + 100))

    assert_raise ArgumentError, fn ->
      GameStore.commit(Repo, world, restored.epoch, restored, unsupported)
    end

    assert :ok == FinancialLedger.audit(Repo, world)

    # A partial sale creates a consumed child and an owned remainder, and posts COGS.
    at_port = put_in(restored, [:entities, "ships", other["id"], "port"], "Singapore")

    sell = %{
      "action" => "sell",
      "ship" => other["id"],
      "good" => "Fruit",
      "quantity" => 1,
      "limit" => 1
    }

    {:ok, sold, _} =
      Game.execute(at_port, account, sell, %{}, TijaraTides.Infrastructure.GameCatalogue.all())

    assert {:ok, :ok} = GameStore.commit(Repo, world, restored.epoch, restored, sold)
    [remainder] = sold.entities["ships"][other["id"]]["cargo"]
    assert remainder["quantity"] == 1
    refute remainder["lot_id"] == cargo["lot_id"]

    assert [[2, 2]] ==
             Repo.query!(
               "SELECT sum(original_quantity_lots)::bigint,count(*) FROM game_cargo_lots WHERE world_id=$1 AND parent_lot_id=$2",
               [world, cargo["lot_id"]]
             ).rows

    assert :ok == FinancialLedger.audit(Repo, world)
  end

  defp advance(server, ms) do
    :sys.replace_state(server, fn state -> %{state | last_mono: state.last_mono - ms} end)
    send(server, :tick)
    GameServer.snapshot(nil, server)
  end
end
