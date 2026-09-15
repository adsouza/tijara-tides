defmodule TijaraTidesWeb.DestinationPickerTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest
  alias TijaraTides.UseCases.GameQueries
  alias TijaraTidesWeb.GameUI.DestinationPicker
  alias TijaraTides.Localization

  defp fixture do
    definitions = %{
      catalogue: %{
        "goods" => %{
          "a" => %{"name" => "Lumber", "hold" => "dry", "manual" => true},
          "b" => %{"name" => "Grain", "hold" => "dry", "manual" => true},
          "c" => %{"name" => "Crude oil", "hold" => "liquid", "manual" => true}
        },
        "ports" => Map.new(["Singapore", "Colombo", "Dubai", "Tokyo"], &{&1, %{}}),
        "routes" => %{
          "Singapore|Colombo" => %{"nautical_miles" => 500},
          "Singapore|Dubai" => %{"nautical_miles" => 900}
        }
      }
    }

    quote = fn stock, demand, ask, bid ->
      %{
        "manual" => true,
        "stock" => stock,
        "demand" => demand,
        "ask" => ask,
        "bid" => bid,
        "handling_fee" => 10
      }
    end

    view = %{
      markets: %{
        "Singapore|a" => quote.(50, 0, 100, 80),
        "Colombo|a" => quote.(0, 20, 220, 200),
        "Dubai|a" => quote.(0, 30, 180, 160),
        "Singapore|b" => quote.(0, 10, 200, 180),
        "Colombo|b" => quote.(40, 0, 100, 80),
        "Dubai|b" => quote.(30, 0, 300, 280)
      }
    }

    {definitions, view,
     %{"class" => "small_freighter", "status" => "docked", "port" => "Singapore"}}
  end

  test "matrix computes both directions, handling-adjusted ROI, market lots and ranking" do
    {definitions, view, ship} = fixture()
    matrix = GameQueries.destination_matrix(definitions, view, ship)
    assert Enum.map(matrix.rows, & &1.port) == ["Colombo", "Dubai"]
    assert Enum.map(matrix.goods, &elem(&1, 0)) == ["b", "a"]
    first = hd(matrix.rows)
    assert_in_delta first.cells["a"].outbound.roi, 80 / 110, 0.00001
    assert first.cells["a"].outbound.lots == 20
    assert first.cells["a"].inbound == nil
    assert first.cells["b"].inbound.lots == 10
    assert List.last(matrix.rows).cells["b"].inbound.roi < 0

    assert GameQueries.destination_matrix(definitions, view, %{ship | "status" => "sailing"}) ==
             %{goods: [], rows: []}

    dry = put_in(view, [:markets, "Singapore|a", "stock"], 0)

    assert hd(GameQueries.destination_matrix(definitions, dry, ship).rows).cells["a"].outbound ==
             nil
  end

  test "aboard cargo remains visible without local stock and uses cost of the lots a buyer can take" do
    {definitions, view, ship} = fixture()
    view = put_in(view, [:markets, "Singapore|a", "stock"], 0)

    ship =
      Map.put(ship, "cargo", [
        %{"good" => "a", "quantity" => 10, "unit_cost" => 100},
        %{"good" => "a", "quantity" => 30, "unit_cost" => 200}
      ])

    matrix = GameQueries.destination_matrix(definitions, view, ship)
    assert {"a", definitions.catalogue["goods"]["a"]} in matrix.goods
    opportunity = Enum.find(matrix.rows, &(&1.port == "Colombo")).cells["a"].outbound
    assert opportunity.source == :aboard
    assert opportunity.lots == 20
    assert opportunity.proceeds == 3800
    assert_in_delta opportunity.roi, 800 / 3000, 0.00001

    html =
      render_component(&DestinationPicker.panel/1,
        definitions: definitions,
        view: view,
        ship: ship
      )

    assert html =~ "Sell aboard cargo"
    tree = LazyHTML.from_fragment(html)
    assert LazyHTML.query(tree, ".outbound rect") |> LazyHTML.to_html() =~ ~s(fill="currentColor")
    assert LazyHTML.query(tree, ".outbound circle") |> LazyHTML.to_html() == ""

    view = put_in(view, [:markets, "Colombo|a", "demand"], 0)
    view = put_in(view, [:markets, "Dubai|a", "demand"], 0)
    matrix = GameQueries.destination_matrix(definitions, view, ship)
    assert {"a", definitions.catalogue["goods"]["a"]} in matrix.goods
    assert Enum.all?(matrix.rows, &is_nil(&1.cells["a"].outbound))
  end

  test "zero-cost cargo shows sale proceeds without inventing an ROI" do
    {definitions, view, ship} = fixture()
    ship = Map.put(ship, "cargo", [%{"good" => "a", "quantity" => 5, "unit_cost" => 0}])
    matrix = GameQueries.destination_matrix(definitions, view, ship)
    opportunity = Enum.find(matrix.rows, &(&1.port == "Colombo")).cells["a"].outbound
    assert opportunity.roi == nil
    assert opportunity.lots == 5

    html =
      render_component(&DestinationPicker.panel/1,
        definitions: definitions,
        view: view,
        ship: ship
      )

    assert html =~ "ROI unavailable for zero-cost cargo"
  end

  test "ranking includes the best return opportunity, not just outbound" do
    {definitions, view, ship} = fixture()
    view = put_in(view, [:markets, "Dubai|b", "ask"], 50)
    [dubai, colombo] = GameQueries.destination_matrix(definitions, view, ship).rows
    assert dubai.port == "Dubai"
    assert colombo.port == "Colombo"
    assert dubai.cells["a"].outbound.roi < colombo.cells["a"].outbound.roi

    assert_in_delta dubai.best,
                    dubai.cells["a"].outbound.roi + dubai.cells["b"].inbound.roi,
                    0.00001
  end

  test "popup localizes names, has colored sized discs, and ports use the destination event" do
    {definitions, view, ship} = fixture()

    for locale <- ["en", "ar"] do
      html =
        Localization.with_locale(locale, fn ->
          render_component(&DestinationPicker.panel/1,
            definitions: definitions,
            view: view,
            ship: ship
          )
        end)

      tree = LazyHTML.from_fragment(html)
      assert html =~ ~s(role="dialog")
      assert html =~ ~s(phx-click="preview")
      assert html =~ ~s(phx-value-destination="Colombo")
      assert html =~ ~s(phx-key="Escape")

      assert LazyHTML.query(tree, ".outbound circle") |> LazyHTML.to_html() =~
               ~s(fill="currentColor")

      assert LazyHTML.query(tree, ".inbound .opportunity-skull") |> LazyHTML.text() =~ "☠"

      if locale == "ar" do
        assert html =~ "كولومبو"
        assert html =~ "فرص التجارة"
        refute LazyHTML.text(tree) =~ "Outbound"
      end
    end
  end
end
