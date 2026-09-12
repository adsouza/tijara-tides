defmodule TijaraTidesWeb.LobbyLocalizationTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest
  alias TijaraTides.Localization
  alias TijaraTidesWeb.LobbyLive

  test "online-player count uses the selected locale including zero" do
    for {locale, count, expected} <- [
          {"en", 12, "12"},
          {"ar", 12, "١٢"},
          {"ar", 0, "٠"}
        ] do
      html =
        Localization.with_locale(locale, fn ->
          render_component(&LobbyLive.render/1, snapshot: %{online_players: count}, flash: %{})
        end)

      value =
        html |> LazyHTML.from_fragment() |> LazyHTML.query("#online-players") |> LazyHTML.text()

      assert String.trim(value) == expected
    end
  end
end
