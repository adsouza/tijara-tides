defmodule TijaraTidesWeb.GameUI.ShipyardTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest
  alias TijaraTides.Localization
  alias TijaraTides.UseCases.{Game, GameQueries}
  alias TijaraTidesWeb.GameUI.{FleetPanel, Presentation}

  defp panel(definitions, port, cash \\ 10_000_000, selected \\ true) do
    render_component(&FleetPanel.panel/1,
      first_ship_port_selected: selected,
      definitions: definitions,
      destination: nil,
      fleet_status: "all",
      inspected_ship: nil,
      instruction_drafts: %{},
      manifest_sort: {"good", :asc},
      preview: nil,
      request_id: "request",
      route_drafts: %{},
      selected_port: port,
      selected_ship: nil,
      ship: nil,
      view: %{
        public: %{"ships" => %{}},
        private: %{
          "company" => %{"cash" => cash, "reserved" => 0},
          "account" => %{},
          "ships" => %{}
        }
      }
    )
  end

  test "every port renders only purchasable controls and hides empty shipyards" do
    definitions = Game.definitions()

    for port <- Map.keys(definitions.catalogue["ports"]) do
      offered = GameQueries.shipyard(definitions, port).classes
      tree = panel(definitions, port) |> LazyHTML.from_fragment()
      buttons = LazyHTML.query(tree, "#shipyard-purchase button[name=class]")
      assert Enum.sort(LazyHTML.attribute(buttons, "value")) == Enum.sort(Map.keys(offered)), port

      if map_size(offered) == 0 do
        assert LazyHTML.query(tree, "#shipyard") |> Enum.empty?()
        assert LazyHTML.query(tree, "#first-ship-port") |> Enum.count() == 1
        assert LazyHTML.query(tree, "#shipyard-purchase") |> Enum.empty?()
      else
        assert LazyHTML.attribute(buttons, "disabled") == []
        assert LazyHTML.query(tree, "#first-ship-port") |> Enum.empty?()
      end
    end
  end

  test "an empty fleet starts with an open unselected chooser and ranked concise options" do
    tree = panel(Game.definitions(), "Guangzhou", 0, false) |> LazyHTML.from_fragment()
    assert LazyHTML.query(tree, "#shipyard") |> Enum.empty?()
    assert LazyHTML.query(tree, "#first-ship-port summary") |> Enum.empty?()

    assert LazyHTML.query(tree, "#first-ship-port label") |> LazyHTML.text() |> String.trim() ==
             "Buy your 1st ship at"

    options = LazyHTML.query(tree, "#first-ship-port-select option")

    assert LazyHTML.query(tree, "#first-ship-port-select option[selected]")
           |> LazyHTML.attribute("value") == [""]

    assert LazyHTML.attribute(options, "value") == [
             "",
             "Guangzhou",
             "Busan",
             "Shanghai",
             "Colombo",
             "Abu Dhabi",
             "Ho Chi Minh City",
             "Mumbai",
             "Rotterdam",
             "Manila",
             "Tokyo"
           ]

    assert LazyHTML.text(options) =~
             "Guangzhou (Small freighter, Freighter, Bulk, Reefer, Tanker)"

    assert LazyHTML.text(options) =~ "Tokyo (Bulk)"
    assert LazyHTML.text(options) =~ "Manila (Tanker)"
  end

  test "available offers remain disabled below their unreserved price and enabled at it" do
    definitions = Game.definitions()

    for {cash, disabled} <- [{2_999_999, true}, {3_000_000, false}] do
      button =
        panel(definitions, "Guangzhou", cash)
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("button[name=class][value=small_freighter]")

      assert LazyHTML.attribute(button, "disabled") != [] == disabled
    end
  end

  test "regional yard names, empty states and rejection messages translate into Arabic" do
    definitions = Game.definitions()

    Localization.with_locale("ar", fn ->
      for port <- ["Tokyo", "Manila", "Rotterdam"] do
        region = GameQueries.shipyard(definitions, port).region
        html = panel(definitions, port)
        assert html =~ Localization.l10n(region)
        assert Localization.l10n(region) =~ ~r/\p{Arabic}/u
        refute html =~ region
      end

      html = panel(definitions, "Jakarta")
      assert html =~ Localization.l10n("Guangzhou")
      refute html =~ "Buy your 1st ship at"
      refute html =~ "Choose a port"
      refute html =~ "(Small freighter, Freighter, Bulk, Reefer, Tanker)"
      message = Presentation.error_message(:ship_class_unavailable)
      assert message =~ ~r/\p{Arabic}/u
      refute message =~ "not offered"
    end)
  end
end
