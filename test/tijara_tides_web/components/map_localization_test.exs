defmodule TijaraTidesWeb.MapLocalizationTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest
  alias TijaraTides.Localization
  alias TijaraTidesWeb.GameUI.MapPanel

  test "region headings and marker labels translate while navigation IDs stay stable" do
    definitions = TijaraTides.UseCases.Game.definitions()
    definitions = %{definitions | land: [], regional_land: %{}}

    render = fn region ->
      Localization.with_locale("ar", fn ->
        render_component(&MapPanel.panel/1,
          definitions: definitions,
          inspected_ship: nil,
          map_filters_open: false,
          map_region: region,
          map_ship_classes: [],
          map_ships: [],
          map_show_others: true,
          selected_port: "Singapore",
          view: %{private: nil, public: %{"clock_ms" => 0}}
        )
      end)
    end

    world = render.(nil)

    for {name, translated} <- [
          {"Strait of Hormuz", "مضيق هرمز"},
          {"Northern Frangistan", "فرنجيستان الشمالية"},
          {"Pearl River Delta", "دلتا نهر اللؤلؤ"}
        ] do
      assert world =~ ~s(phx-value-id="#{name}")
      assert world =~ translated

      marker_count =
        world
        |> LazyHTML.from_fragment()
        |> LazyHTML.query(~s(g[phx-value-id="#{name}"] text))
        |> LazyHTML.text()
        |> String.trim()

      assert marker_count == if(name == "Strait of Hormuz", do: "٢", else: "٣")
      regional = render.(name) |> LazyHTML.from_fragment()
      assert LazyHTML.query(regional, ".map-region-heading h2") |> LazyHTML.text() == translated
      assert LazyHTML.query(regional, "#region-ports") |> LazyHTML.text() =~ translated
    end
  end
end
