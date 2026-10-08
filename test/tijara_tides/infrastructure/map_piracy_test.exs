defmodule TijaraTides.Infrastructure.MapPiracyTest do
  use ExUnit.Case, async: false
  @moduletag :game_database
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  alias TijaraTides.Domain.{Piracy, PiracyWorld}
  alias TijaraTides.Infrastructure.GameServer
  alias TijaraTides.SqlReplay, as: Sql
  @endpoint TijaraTidesWeb.Endpoint

  setup_all do
    Sql.repo()
  end

  defp query(view, selector),
    do: render(view) |> LazyHTML.from_fragment() |> LazyHTML.query(selector)

  test "the map shades pirate zones and lists announced campaigns" do
    Sql.with_world(fn c ->
      {conn, token} = TijaraTides.WebFormFixture.session(c)
      catalogue = :sys.get_state(c.server).catalogue
      model = Piracy.model(catalogue)

      campaign =
        Enum.find_value(1..1_000, fn slot ->
          Enum.find_value(Enum.sort(Map.keys(model["zones"])), &Piracy.campaign(&1, slot, model))
        end)

      at = campaign["announced_ms"]
      before = :sys.get_state(c.server).game
      Sql.persist(c, PiracyWorld.refresh(%{before | clock_ms: at}, catalogue))
      expected = Piracy.campaigns(at, model)

      {:ok, view, _} = conn |> recycle() |> live("/play")
      assert Enum.count(query(view, "#world-map [data-piracy-zone]")) == 5
      assert has_element?(view, "[data-piracy-zone='#{campaign["id"]}'][data-level='elevated']")
      assert Enum.count(query(view, "#piracy-campaigns li")) == map_size(expected)
      assert has_element?(view, "#piracy-campaigns li", campaign["name"])
      mark = model["kinds"][model["zones"][campaign["id"]]["kind"]]["mark"]
      assert has_element?(view, "#piracy-campaigns li .ui-emoji", mark)

      assert {:ok, _} =
               GameServer.command(
                 token,
                 "piracy-locale-ar",
                 %{"action" => "locale", "locale" => "ar"},
                 c.server
               )

      arabic =
        TijaraTides.Localization.with_locale("ar", fn ->
          TijaraTides.Localization.l10n(model["zones"][campaign["id"]]["name"])
        end)

      {:ok, view, _} = conn |> recycle() |> live("/play")
      assert has_element?(view, "#piracy-campaigns li", arabic)
    end)
  end
end
