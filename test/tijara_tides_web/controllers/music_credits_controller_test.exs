defmodule TijaraTidesWeb.MusicCreditsControllerTest do
  use TijaraTidesWeb.ConnCase, async: true

  test "lists every track's title, creators, source, licence and edits", %{conn: conn} do
    html = conn |> get("/music/credits") |> html_response(200)
    {:ok, manifest} = TijaraTidesWeb.Music.manifest()

    for {slug, track} <- manifest["tracks"] do
      assert html =~ ~s(id="music-credit-#{slug}")
      for key <- ~w(title credit source_url licence edits), do: assert(html =~ track[key])
    end

    assert html =~ "Music credits"
  end
end
