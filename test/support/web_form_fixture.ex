defmodule TijaraTides.WebFormFixture do
  @moduledoc "Legal warehouse/cargo and authenticated web fixtures shared by raw and browser tests."
  use Boundary,
    deps: [
      TijaraTides.Infrastructure,
      TijaraTides.SqlReplay,
      TijaraTides.CompanyFixture,
      TijaraTidesWeb,
      Phoenix,
      Phoenix.LiveViewTest
    ]

  import ExUnit.Callbacks
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  alias TijaraTides.SqlReplay, as: Sql
  alias TijaraTides.Infrastructure.GameServer
  @endpoint TijaraTidesWeb.Endpoint

  def fixture(c) do
    previous = Application.get_env(:tijara_tides, :game_server)
    Application.put_env(:tijara_tides, :game_server, c.server)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:tijara_tides, :game_server, previous),
        else: Application.delete_env(:tijara_tides, :game_server)
    end)

    conn =
      build_conn() |> get("/play") |> recycle() |> post("/session/redeem", %{"code" => c.code})

    token = Plug.Conn.get_session(conn, :account_token)

    {:ok, %{"company_id" => company}} =
      TijaraTides.CompanyFixture.command(
        token,
        "formation",
        %{"action" => "company", "name" => "Forms", "port" => "Jakarta", "package" => "general"},
        c.server
      )

    ship = company <> ":1"

    Sql.command(c, token, "buy-cargo", %{
      "action" => "buy",
      "ship" => ship,
      "good" => "lumber",
      "quantity" => 10,
      "limit" => 1_000_000,
      "destination" => "Singapore"
    })

    Sql.advance(c.server, 60_000)

    Sql.command(c, token, "lease", %{
      "action" => "warehouse_lease",
      "port" => "Jakarta",
      "storage" => "dry",
      "blocks" => 5,
      "days" => 1,
      "price" => 500
    })

    warehouse = GameServer.snapshot(token, c.server).private["warehouses"] |> Map.keys() |> hd()

    Sql.command(c, token, "store-cargo", %{
      "action" => "warehouse_transfer",
      "ship" => ship,
      "warehouse" => warehouse,
      "side" => "store",
      "good" => "lumber",
      "quantity" => 5
    })

    Sql.advance(c.server, 60_000)
    {:ok, view, _} = conn |> recycle() |> live("/play")
    render_click(view, "ship", %{"id" => ship})

    %{
      c: c,
      token: token,
      view: view,
      ship: ship,
      company: company,
      warehouse: warehouse,
      cookie: conn.resp_cookies["_tijara_tides_key"].value
    }
  end
end
