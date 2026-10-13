defmodule TijaraTidesWeb.QueueMarginLiveTest do
  use ExUnit.Case, async: false
  @moduletag :game_database
  alias TijaraTides.Domain.Trade
  alias TijaraTides.Infrastructure.GameServer
  alias TijaraTides.Infrastructure.Persistence.Repo
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

    Ecto.Migrator.run(Repo, TijaraTides.TestMigrations.all(), :up, all: true, log: false)
    :ok
  end

  # A company at Jakarta whose first ship is loading lumber, so its next trade queues.
  setup do
    id = Ecto.UUID.generate()

    server =
      start_supervised!({GameServer, name: nil, enabled: true, world_id: id, tick_ms: 86_400_000})

    {:ok, code} = GameServer.seed(server)
    Application.put_env(:tijara_tides, :game_server, server)
    on_exit(fn -> Application.delete_env(:tijara_tides, :game_server) end)

    conn = build_conn() |> get("/play") |> recycle() |> post("/session/redeem", %{"code" => code})
    token = Plug.Conn.get_session(conn, :account_token)

    {:ok, _} =
      TijaraTides.CompanyFixture.command(
        token,
        "company",
        %{
          "action" => "company",
          "name" => "Margins",
          "port" => "Jakarta",
          "package" => "general"
        },
        server
      )

    [ship, other | _] =
      GameServer.snapshot(token, server).private["ships"] |> Map.keys() |> Enum.sort()

    load = %{
      "action" => "buy",
      "ship" => ship,
      "good" => "lumber",
      "quantity" => 1,
      "limit" => 1_000_000,
      "destination" => "Singapore"
    }

    {:ok, _} = GameServer.command(token, "load", load, server)
    {:ok, view, _} = live(conn, "/play")
    %{view: view, token: token, server: server, ship: ship, other: other}
  end

  defp open_buy(c) do
    render_click(c.view, "ship", %{"id" => c.ship})
    render_change(c.view, "port", %{"id" => "Jakarta"})
    render_change(c.view, "preview", %{"destination" => "Singapore"})

    [_, limit] =
      Regex.run(~r/name="limit" value="(\d+)"/, render(element(c.view, "#trade-buy-lumber")))

    c.view |> form("#trade-buy-lumber", %{"quantity" => "3"}) |> render_submit()
    String.to_integer(limit)
  end

  defp private(c), do: GameServer.snapshot(c.token, c.server).private
  defp pending(c, ship \\ nil), do: private(c)["ships"][ship || c.ship]

  test "a trade that must queue asks for a margin, and confirming queues at the widened limit",
       c do
    limit = open_buy(c)
    assert has_element?(c.view, "#queue-margin-dialog[role=dialog]")
    refute render(c.view) =~ "phx-flash"
    assert pending(c)["pending_side"] == nil

    assert has_element?(
             c.view,
             "#queue-margin-dialog input[type=range][name=margin_bps][value='200']"
           )

    assert has_element?(c.view, "#queue-margin-dialog", "2.0%")
    assert has_element?(c.view, "#queue-margin-dialog input[aria-valuetext='2.0%']")
    # Closing returns keyboard focus to the trade form that opened the dialog.
    assert has_element?(c.view, "#queue-margin-dialog[phx-remove*='trade-buy-lumber']")

    render_change(c.view, "queue-margin-change", %{"margin_bps" => "500"})
    widened = Trade.queued_limit("buy", limit, 500)

    assert has_element?(
             c.view,
             "#queue-margin-worst-case",
             TijaraTides.Localization.money(widened, 2)
           )

    c.view |> form("#queue-margin-form", %{"margin_bps" => "200"}) |> render_submit()
    refute has_element?(c.view, "#queue-margin-dialog")

    ship = pending(c)
    assert ship["pending_side"] == "buy"
    assert ship["pending_quantity"] == 3
    assert ship["pending_limit"] == Trade.queued_limit("buy", limit, 200)
    assert private(c)["account"]["queue_margin_buy_bps"] == nil
  end

  test "cancelling, Escape and a stray confirm queue nothing", c do
    open_buy(c)
    render_click(c.view, "queue-margin-cancel")
    refute has_element?(c.view, "#queue-margin-dialog")

    open_buy(c)
    render_keydown(c.view, "queue-margin-cancel", %{"key" => "Escape"})
    refute has_element?(c.view, "#queue-margin-dialog")

    render_submit(c.view, "queue-margin-confirm", %{"action" => "buy", "margin_bps" => "200"})
    assert pending(c)["pending_side"] == nil
  end

  test "changing the selection while the dialog is open cannot retarget the trade", c do
    limit = open_buy(c)
    render_click(c.view, "ship", %{"id" => c.other})
    render_change(c.view, "preview", %{"destination" => "Guangzhou"})
    c.view |> form("#queue-margin-form", %{"margin_bps" => "0"}) |> render_submit()

    ship = pending(c)
    assert ship["pending_side"] == "buy"
    assert ship["pending_destination"] == "Singapore"
    assert ship["pending_limit"] == limit
    assert pending(c, c.other)["pending_side"] == nil
  end

  test "keeping the margin as the default skips the dialog for the next queued buy", c do
    limit = open_buy(c)

    assert has_element?(
             c.view,
             "#queue-margin-dialog",
             "Use this margin for all future queued buys"
           )

    c.view
    |> form("#queue-margin-form", %{"margin_bps" => "300", "save_margin" => "true"})
    |> render_submit()

    assert private(c)["account"]["queue_margin_buy_bps"] == 300
    assert pending(c)["pending_limit"] == Trade.queued_limit("buy", limit, 300)

    render_click(c.view, "cancel-berth-trade", %{"id" => c.ship})
    assert pending(c)["pending_side"] == nil

    limit = open_buy(c)
    refute has_element?(c.view, "#queue-margin-dialog")
    assert pending(c)["pending_limit"] == Trade.queued_limit("buy", limit, 300)
  end

  test "the trade panel shows, saves and resets each side's default", c do
    render_click(c.view, "ship", %{"id" => c.ship})
    render_change(c.view, "port", %{"id" => "Jakarta"})
    assert has_element?(c.view, "#queue-margin-defaults", "Ask me")

    # Both market sides render their own table; the defaults appear once for the port.
    assert render(c.view)
           |> LazyHTML.from_fragment()
           |> LazyHTML.query("[id='queue-margin-defaults']")
           |> Enum.count() == 1

    refute has_element?(c.view, "#queue-margin-defaults", "%")

    c.view |> form("#queue-margin-default-buy", %{"margin_bps" => "300"}) |> render_submit()
    c.view |> form("#queue-margin-default-sell", %{"margin_bps" => "0"}) |> render_submit()
    assert private(c)["account"]["queue_margin_buy_bps"] == 300
    assert private(c)["account"]["queue_margin_sell_bps"] == 0
    render_click(c.view, "ship", %{"id" => c.ship})
    assert has_element?(c.view, "#queue-margin-defaults", "3.0%")
    assert has_element?(c.view, "#queue-margin-defaults", "0.0%")

    c.view
    |> element("#queue-margin-defaults button[phx-click=queue-margin-reset][phx-value-side=buy]")
    |> render_click()

    assert private(c)["account"]["queue_margin_buy_bps"] == nil
    assert private(c)["account"]["queue_margin_sell_bps"] == 0

    # Back to asking: the next queued buy opens the dialog again.
    open_buy(c)
    assert has_element?(c.view, "#queue-margin-dialog")
  end

  test "an out-of-range saved margin is refused with a message", c do
    render_click(c.view, "ship", %{"id" => c.ship})
    render_change(c.view, "port", %{"id" => "Jakarta"})
    render_submit(c.view, "queue-margin-save", %{"side" => "buy", "margin_bps" => "1001"})
    assert render(c.view) =~ "Choose a queued-trade margin from 0% to 10%."
    assert private(c)["account"]["queue_margin_buy_bps"] == nil
  end
end
