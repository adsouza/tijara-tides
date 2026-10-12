defmodule TijaraTides.Infrastructure.MusicFocusTest do
  use ExUnit.Case, async: false
  @moduletag :game_database
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  alias TijaraTides.SqlReplay, as: Sql
  alias TijaraTides.Infrastructure.GameServer
  @endpoint TijaraTidesWeb.Endpoint

  setup_all do
    Sql.repo()
  end

  defp music(view) do
    node = view |> render() |> LazyHTML.from_fragment() |> LazyHTML.query("#music")

    for name <- ~w(music context port ship origin destination progress), into: %{} do
      {name, node |> LazyHTML.attribute("data-" <> name) |> List.first()}
    end
  end

  defp refreshed(view) do
    send(view.pid, {:game_changed, 0})
    render_async(view)
    music(view)
  end

  defp status(token, c, ship),
    do: GameServer.snapshot(token, c.server).public["ships"][ship]["status"]

  defp progress(attrs) do
    {value, ""} = Float.parse(attrs["progress"])
    assert value >= 0.0 and value <= 1.0
    value
  end

  # Advances until `done?` holds, failing after a bounded number of steps.
  defp advance_until(c, step_ms, done?) do
    Enum.find_value(1..200, fn _ ->
      Sql.advance(c.server, step_ms)
      done?.()
    end) || flunk("condition not reached")
  end

  test "music follows explicit selections, departures, diversions and arrivals" do
    Sql.with_world(fn c ->
      {conn, token} = TijaraTides.WebFormFixture.session(c)

      {:ok, visitor, _} = build_conn() |> live("/play")

      assert %{"music" => "available", "context" => "port", "port" => "Guangzhou", "ship" => nil} =
               music(visitor)

      {:ok, %{"company_id" => company}} =
        TijaraTides.CompanyFixture.command(
          token,
          "formation",
          %{
            "action" => "company",
            "name" => "Music Owners",
            "port" => "Jakarta",
            "package" => "general"
          },
          c.server
        )

      ship = company <> ":1"
      {:ok, view, _} = conn |> recycle() |> live("/play")
      # The first view auto-selects the docked ship; focus starts at its port.
      assert %{"context" => "port", "port" => "Jakarta"} = music(view)

      render_click(view, "port", %{"id" => "Tangier"})
      assert %{"context" => "port", "port" => "Tangier"} = music(view)

      # A destination preview moves selected_port to the ship's port; music stays.
      render_click(view, "preview", %{"destination" => "Singapore"})
      assert has_element?(view, ~s(#port-selector[data-selected="Jakarta"]))
      assert %{"port" => "Tangier"} = music(view)

      render_click(view, "ship", %{"id" => ship})
      assert %{"context" => "port", "port" => "Jakarta", "ship" => nil} = music(view)

      Sql.command(c, token, "sail", %{
        "action" => "sail",
        "ship" => ship,
        "destination" => "Singapore",
        "fuel_limit" => 1_000_000_000
      })

      voyage = refreshed(view)

      assert %{
               "context" => "voyage",
               "ship" => ^ship,
               "origin" => "Jakarta",
               "destination" => "Singapore"
             } =
               voyage

      early = progress(voyage)
      # Routine refreshes keep the ship's context while progress moves. The test
      # catalogue crosses Jakarta to Singapore in 140 s, hence the small step.
      later = advance_until(c, 10_000, fn -> (p = progress(refreshed(view))) > early && p end)

      # A visitor's explicit inspection of a public sailing ship is a ship focus too.
      refreshed(visitor)
      render_click(visitor, "inspect-ship", %{"id" => ship})
      assert %{"context" => "voyage", "ship" => ^ship, "origin" => "Jakarta"} = music(visitor)

      Sql.command(c, token, "reroute", %{
        "action" => "reroute",
        "ship" => ship,
        "destination" => "Ho Chi Minh City",
        "fuel_limit" => 1_000_000_000
      })

      diverted = refreshed(view)
      assert %{"origin" => "Jakarta", "destination" => "Ho Chi Minh City"} = diverted
      assert progress(diverted) < later

      advance_until(c, 3_600_000, fn -> status(token, c, ship) != "sailing" end)
      assert %{"context" => "port", "port" => "Ho Chi Minh City", "ship" => nil} = refreshed(view)
    end)
  end
end
