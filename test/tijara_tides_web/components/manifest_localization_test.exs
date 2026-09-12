defmodule TijaraTidesWeb.ManifestLocalizationTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest
  alias TijaraTides.Localization
  alias TijaraTidesWeb.GameUI.FleetPanel

  test "Arabic manifest headers translate without changing sort column identifiers" do
    definitions = TijaraTides.UseCases.Game.definitions()
    definitions = %{definitions | land: [], regional_land: %{}}
    {class, _} = Enum.find(definitions.classes, fn {_, spec} -> spec["hold"] == "dry" end)

    {good, _} =
      Enum.find(definitions.catalogue["goods"], fn {_, item} -> item["name"] == "Lumber" end)

    ship = %{
      "id" => "ship",
      "name" => "Test ship",
      "class" => class,
      "port" => "Singapore",
      "status" => "loading",
      "arrive_ms" => 1_230_000,
      "book_value" => 100_000,
      "cargo" => [%{"good" => good, "quantity" => 2, "unit_cost" => 100, "expires_ms" => nil}]
    }

    html =
      Localization.with_locale("ar", fn ->
        render_component(&FleetPanel.panel/1,
          definitions: definitions,
          destination: nil,
          fleet_status: "all",
          inspected_ship: nil,
          instruction_drafts: %{},
          manifest_sort: {"good", :asc},
          map_filters_open: false,
          map_region: nil,
          map_ship_classes: [],
          map_ships: [],
          map_show_others: true,
          preview: nil,
          request_id: "request",
          route_drafts: %{},
          selected_port: "Singapore",
          selected_ship: "ship",
          ship: ship,
          view: %{
            public: %{"clock_ms" => 0},
            private: %{
              "ships" => %{"ship" => ship},
              "company" => %{"cash" => 100_000, "reserved" => 0},
              "voyage_freshness" => %{"ship" => []}
            }
          }
        )
      end)

    tree = LazyHTML.from_fragment(html)
    card = LazyHTML.query(tree, ".fleet-list button") |> LazyHTML.text()
    assert card =~ "متبقٍ ٢٠٫٥ دقيقة"
    refute card =~ "20.5"

    for {column, translation} <- [
          {"good", "البضائع"},
          {"quantity", "الدفعات"},
          {"weight", "الوزن"},
          {"volume", "الحجم"},
          {"average_cost", "متوسط التكلفة"},
          {"expires_ms", "أقرب انتهاء صلاحية"}
        ] do
      header =
        LazyHTML.query(tree, ~s(button[phx-click="sort-manifest"][phx-value-column="#{column}"]))
        |> LazyHTML.text()

      assert header =~ translation
    end
  end
end
