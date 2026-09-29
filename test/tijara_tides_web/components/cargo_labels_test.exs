defmodule TijaraTidesWeb.CargoLabelsTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest
  alias TijaraTides.UseCases.Game
  alias TijaraTidesWeb.GameUI.Presentation

  test "every catalogue cargo has a distinct emoji and its readable name" do
    goods = Game.definitions().catalogue["goods"]
    symbols = Enum.map(Map.keys(goods), &Presentation.cargo_emoji/1)
    refute "📦" in symbols
    assert length(Enum.uniq(symbols)) == map_size(goods)

    for {id, _} <- goods do
      tree =
        render_component(&Presentation.cargo_label/1, good: id)
        |> LazyHTML.from_fragment()

      assert LazyHTML.query(tree, ".ui-emoji") |> LazyHTML.text() == Presentation.cargo_emoji(id)
      assert LazyHTML.query(tree, ".ui-emoji") |> LazyHTML.attribute("aria-hidden") == ["true"]
      assert LazyHTML.text(tree) =~ Presentation.cargo_name(id)
    end
  end

  test "unknown cargo uses a generic icon while retaining an explicit catalogue name" do
    tree =
      render_component(&Presentation.cargo_label/1, good: "new-cargo", name: "New cargo")
      |> LazyHTML.from_fragment()

    assert LazyHTML.text(tree) =~ "New cargo"
    assert LazyHTML.query(tree, ".ui-emoji") |> LazyHTML.text() == "📦"
    assert Presentation.cargo_option("new-cargo", "New cargo") == "📦 New cargo"
  end
end
