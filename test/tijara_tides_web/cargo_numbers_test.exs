defmodule TijaraTidesWeb.CargoNumbersTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest
  alias TijaraTides.Localization
  alias TijaraTidesWeb.GameUI.CargoPanel

  test "Arabic market tables localize stock, demand and route distances" do
    definitions = TijaraTides.UseCases.Game.definitions()

    {good, _} =
      Enum.find(definitions.catalogue["goods"], fn {_, item} -> item["name"] == "Lumber" end)

    catalogue =
      definitions.catalogue
      |> Map.put("ports", %{
        "Singapore" => %{"roles" => %{good => "++exp"}},
        "Colombo" => %{"roles" => %{good => "++imp"}}
      })
      |> Map.put("routes", %{"Singapore|Colombo" => %{"nautical_miles" => 1609}})

    quote = %{
      "manual" => true,
      "stock" => 500,
      "demand" => 500,
      "buyer_budget" => 15_119,
      "ask" => 100,
      "bid" => 120
    }

    html =
      Localization.with_locale("ar", fn ->
        render_component(&CargoPanel.panel/1,
          definitions: %{definitions | catalogue: catalogue},
          view: %{markets: %{("Singapore|" <> good) => quote, ("Colombo|" <> good) => quote}},
          ship: %{
            "status" => "docked",
            "port" => "Singapore",
            "class" => hd(Map.keys(definitions.classes))
          },
          market_good: good,
          market_sort: %{"supply" => {"ask", :asc}, "demand" => {"bid", :desc}},
          cargo_filter_ship: false,
          cargo_menu_open: true,
          cargo_sort_roi: false,
          cargo_roi_varies: false,
          cargo_options: [{good, %{label: "—", roi: 0.125}}]
        )
      end)

    tree = LazyHTML.from_fragment(html)
    roi = LazyHTML.query(tree, "#cargo-options button .cargo-roi") |> LazyHTML.text()
    assert roi =~ "١٢٫٥٠٪"
    refute roi =~ "12.50%"
    headings = LazyHTML.query(tree, ".cargo-comparison h3") |> LazyHTML.text()
    assert headings =~ "العرض"
    assert headings =~ "الطلب"
    refute headings =~ "Supply"
    refute headings =~ "Demand"
    assert LazyHTML.query(tree, "#cargo-supply thead") |> LazyHTML.text() =~ "العرض"
    assert LazyHTML.query(tree, "#cargo-supply tbody") |> LazyHTML.text() =~ "٥٠٠"
    demand = LazyHTML.query(tree, "#cargo-demand tbody") |> LazyHTML.text()
    assert demand =~ "١٢٥"
    assert demand =~ "١٦٠٩"
    refute demand =~ "1609"
    assert LazyHTML.query(tree, "#cargo-demand thead") |> LazyHTML.text() =~ "ميل بحري"
  end
end
