defmodule TijaraTidesWeb.WarehouseSelectorTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest

  test "lease selector lists three storage types and restricts dedicated cargo to liquids" do
    definitions = TijaraTides.UseCases.Game.definitions()

    view = %{
      public: %{"clock_ms" => 0},
      private: %{"company" => %{"unpaid" => 0, "cash" => 100_000, "reserved" => 0}}
    }

    for kind <- ["dry", "reefer", "liquid"] do
      draft = %{"storage" => kind, "good" => "jewelry"}

      options =
        TijaraTides.UseCases.GameQueries.warehouse_options(definitions, view, "Dubai", draft, nil)

      assert options.storage == kind

      if kind == "liquid",
        do: assert(definitions.catalogue["goods"][options.good]["hold"] == "liquid"),
        else: assert(is_nil(options.good))

      html =
        render_component(&TijaraTidesWeb.GameUI.WarehousePanel.panel/1,
          definitions: definitions,
          view: view,
          port: "Dubai",
          ship: nil,
          draft: draft,
          request_id: "test"
        )

      tree = LazyHTML.from_fragment(html)

      assert LazyHTML.query(tree, "#warehouse-lease-form select[name=storage] option")
             |> LazyHTML.attribute("value") == ["dry", "reefer", "liquid"]

      if kind == "dry", do: assert(html =~ "non-perishable solid goods")

      for {id, _} <- options.storage_goods[kind], kind != "dry" do
        assert html =~ TijaraTidesWeb.GameUI.Presentation.cargo_name(id)
      end

      cargo =
        LazyHTML.query(tree, "#warehouse-lease-form select[name=good] option")
        |> LazyHTML.attribute("value")

      if kind == "liquid",
        do: assert(cargo == Enum.map(options.storage_goods[kind], &elem(&1, 0))),
        else: assert(cargo == [])
    end
  end
end
