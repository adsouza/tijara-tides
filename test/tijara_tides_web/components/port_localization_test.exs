defmodule TijaraTidesWeb.PortLocalizationTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest
  alias TijaraTides.Localization
  alias TijaraTidesWeb.GameUI.PortsPanel

  test "sell market distinguishes affordable lots from nominal demand" do
    definitions = TijaraTides.UseCases.Game.definitions()

    markets =
      Map.new(definitions.catalogue["goods"], fn {good, _} ->
        {"Antwerp|" <> good, %{"manual" => false}}
      end)

    markets =
      Map.put(markets, "Antwerp|iron_ore", %{
        "manual" => true,
        "stock" => 0,
        "demand" => 489,
        "bid" => 14000,
        "buyer_budget" => 30000,
        "handling_fee" => 100
      })

    html =
      render_component(&PortsPanel.panel/1,
        definitions: definitions,
        destination: nil,
        port_market_side: "sell",
        preview: nil,
        purchase_good: nil,
        request_id: "request",
        selected_port: "Antwerp",
        ship: nil,
        trade_limits: %{},
        trade_quantities: %{},
        traffic_grouping: "status",
        view: %{private: nil, public: %{"ships" => %{}}, markets: markets}
      )

    text =
      html
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("#port-market-table-sell")
      |> LazyHTML.text()

    assert text =~ "Sell / buyer capacity"
    assert text =~ "Can buy now: 2 lots · demand: 489 · buyer funds: $300.00"
  end

  test "all port descriptions and selector labels translate without changing port IDs" do
    definitions = TijaraTides.UseCases.Game.definitions()
    ports = definitions.catalogue["ports"]
    assert map_size(ports) == 25

    markets =
      for port <- Map.keys(ports),
          good <- Map.keys(definitions.catalogue["goods"]),
          into: %{},
          do: {port <> "|" <> good, %{"manual" => false, "stock" => 0, "demand" => 0}}

    for {port, entry} <- ports, side <- ["buy", "sell"] do
      Localization.with_locale("en", fn ->
        for text <- [port, entry["harbor"], entry["identity"]] do
          assert Localization.l10n(text) == text
        end
      end)

      Localization.with_locale("ar", fn ->
        for text <- [port, entry["harbor"], entry["identity"]] do
          assert Localization.l10n(text) =~ ~r/\p{Arabic}/u
          refute Localization.l10n(text) == text
        end

        html =
          render_component(&PortsPanel.panel/1,
            definitions: definitions,
            destination: nil,
            port_market_side: side,
            preview: nil,
            purchase_good: nil,
            request_id: "request",
            selected_port: port,
            ship: nil,
            trade_limits: %{},
            trade_quantities: %{},
            traffic_grouping: "status",
            view: %{private: nil, public: %{"ships" => %{}}, markets: markets}
          )

        tree = LazyHTML.from_fragment(html)
        text = LazyHTML.text(tree)

        assert text =~
                 Localization.text(
                   "No cargo is available to %{value1} here right now.",
                   %{value1: Localization.l10n(side)}
                 )

        refute text =~ "buy"
        refute text =~ "sell"

        assert LazyHTML.query(tree, "#about-port > p") |> LazyHTML.text() |> String.trim() ==
                 Localization.l10n(entry["identity"])

        assert html =~ ~s(value="#{port}")

        label =
          LazyHTML.query(tree, ~s(#port-selector option[value="#{port}"])) |> LazyHTML.text()

        assert String.trim(label) == Localization.l10n(port)
      end)
    end
  end
end
