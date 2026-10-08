defmodule TijaraTides.Infrastructure.PublicFleetTest do
  use ExUnit.Case, async: false
  @moduletag :game_database
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  alias TijaraTides.SqlReplay, as: Sql
  @endpoint TijaraTidesWeb.Endpoint

  setup_all do
    Sql.repo()
  end

  defp texts(view, selector) do
    render(view)
    |> LazyHTML.from_fragment()
    |> LazyHTML.query(selector)
    |> Enum.map(&(&1 |> LazyHTML.text() |> String.split() |> Enum.join(" ")))
  end

  defp group_labels(view), do: texts(view, "#public-fleet details > summary")

  test "visitors without a company see every public ship, grouped by location by default" do
    Sql.with_world(fn c ->
      {conn, token} = TijaraTides.WebFormFixture.session(c)

      # Signed in, but without a company yet.
      {:ok, pending, _} = conn |> recycle() |> live("/play")
      assert has_element?(pending, "#public-fleet")

      {:ok, %{"company_id" => company}} =
        TijaraTides.CompanyFixture.command(
          token,
          "formation",
          %{
            "action" => "company",
            "name" => "Fleet Owners",
            "port" => "Jakarta",
            "package" => "general"
          },
          c.server
        )

      ship = company <> ":1"

      # A card for a ship in port selects that port and switches to the Ports panel.
      {:ok, docked, _} = build_conn() |> live("/play")
      refute has_element?(docked, "#port-traffic", "Ships currently at Jakarta")
      docked |> element(~s(#public-fleet [data-public-ship="#{ship}"])) |> render_click()
      assert_push_event(docked, "workspace-panel", %{panel: 2})
      assert has_element?(docked, ~s([data-public-ship="#{ship}"][aria-pressed=true]))
      assert has_element?(docked, "#port-traffic", "Ships currently at Jakarta")

      Sql.command(c, token, "sail", %{
        "action" => "sail",
        "ship" => ship,
        "destination" => "Hamburg",
        "fuel_limit" => 1_000_000_000
      })

      public = TijaraTides.Infrastructure.GameServer.snapshot(token, c.server).public["ships"]
      assert public[ship]["status"] == "sailing"

      {:ok, owner, _} = conn |> recycle() |> live("/play")
      refute has_element?(owner, "#public-fleet")

      {:ok, view, _} = build_conn() |> live("/play")

      assert view |> element("#public-fleet-grouping select option[selected]") |> render() =~
               "Location"

      assert length(texts(view, "#public-fleet [data-public-ship]")) == map_size(public)

      assert Enum.any?(
               group_labels(view),
               &String.starts_with?(&1, "Jakarta ↔ Northern Frangistan")
             )

      assert has_element?(view, ~s(#public-fleet [data-public-ship="#{ship}"]), "Fleet Owners")

      render_change(view, "public-fleet-grouping", %{"grouping" => "company"})
      assert Enum.any?(group_labels(view), &String.starts_with?(&1, "Fleet Owners"))

      render_change(view, "public-fleet-grouping", %{"grouping" => "class"})
      labels = group_labels(view)
      render_change(view, "public-fleet-grouping", %{"grouping" => "anything"})
      assert group_labels(view) == labels

      # The selected card is the summary; there is no separate inspector.
      view |> element(~s(#public-fleet [data-public-ship="#{ship}"])) |> render_click()
      assert has_element?(view, ~s([data-public-ship="#{ship}"][aria-pressed=true]))
      refute has_element?(view, "#public-ship-inspector")
      assert_push_event(view, "workspace-panel", %{panel: 0, scroll_to: "public-ship-" <> ^ship})
    end)
  end
end
