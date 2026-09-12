defmodule TijaraTidesWeb.ShipRouteLocalizationTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest
  alias TijaraTides.Localization
  alias TijaraTidesWeb.ShipRouteEditor

  test "Arabic route targets translate dynamic labels but keep machine values intact" do
    good = %{"name" => "Lumber"}

    stops = [
      %{"id" => "a", "port" => "Singapore", "position" => 0},
      %{"id" => "b", "port" => "Colombo", "position" => 1}
    ]

    for side <- ["buy", "sell"], mode <- ["maximum", "fixed"], editing <- [false, true] do
      draft = %{
        "side" => side,
        "quantity_mode" => mode,
        "good" => "cargo",
        "quantity" => 3,
        "limit" => "12.00",
        "budget" => ""
      }

      draft = if editing, do: Map.put(draft, "rule", "rule"), else: draft

      rule = %{
        "id" => "rule",
        "side" => side,
        "quantity_mode" => mode,
        "good" => "cargo",
        "quantity" => 3,
        "limit" => 1200,
        "budget" => nil
      }

      model = %{
        route: %{
          "status" => "paused",
          "phase" => "arrival",
          "cursor" => 0,
          "stop_after" => false,
          "reason" => "Completing loading targets"
        },
        stops: stops,
        rules: %{"a" => [rule]},
        stop_goods:
          Map.new(stops, &{&1["id"], %{"buy" => [{"cargo", good}], "sell" => [{"cargo", good}]}}),
        plan: %{"departure_wait" => "Waiting for cargo orders to be filled or cancelled"},
        orders: [
          %{
            "id" => "order",
            "side" => side,
            "good" => "cargo",
            "filled" => 0,
            "quantity" => 3,
            "status" => "waiting",
            "reason" => "Waiting for the limit price"
          }
        ]
      }

      html =
        Localization.with_locale("ar", fn ->
          render_component(&ShipRouteEditor.panel/1,
            ship: %{"id" => "ship", "port" => "Singapore"},
            model: model,
            catalogue: %{
              "goods" => %{"cargo" => good},
              "ports" => %{"Singapore" => %{}, "Colombo" => %{}}
            },
            drafts: %{"a" => draft},
            request_id: "request"
          )
        end)

      refute html =~ "Completing loading targets"
      refute html =~ "Waiting for the limit price"
      refute html =~ "Waiting for cargo orders to be filled or cancelled"
      assert html =~ "جارٍ إكمال أهداف التحميل"
      assert html =~ "بانتظار السعر المحدد"
      assert html =~ "بانتظار تنفيذ أوامر البضائع أو إلغائها"
      refute html =~ "Resume route"
      refute html =~ "Add cargo target"
      refute html =~ "Edit cargo target"
      refute html =~ "Buy maximum"
      refute html =~ "Sell all aboard"
      refute html =~ "Lumber"
      refute html =~ "lots of"
      assert html =~ ~s(value="maximum")
      assert html =~ ~s(value="resume")
      assert html =~ ~s(value="cargo")
      tree = LazyHTML.from_fragment(html)

      quantity =
        LazyHTML.query(
          tree,
          "#route-editor-a-#{if editing, do: "rule", else: "new"} input[name=quantity][disabled]"
        )

      assert LazyHTML.to_html(quantity) != "" == (mode == "maximum")
    end
  end
end
