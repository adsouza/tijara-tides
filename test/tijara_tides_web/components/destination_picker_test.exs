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
          "a" => %{
            "name" => "Lumber",
            "hold" => "dry",
            "manual" => true,
            "weight_kg" => 1000,
            "volume_l" => 1000
          },
          "b" => %{
            "name" => "Grain",
            "hold" => "dry",
            "manual" => true,
            "weight_kg" => 1000,
            "volume_l" => 1000
          },
          "c" => %{
            "name" => "Crude oil",
            "hold" => "liquid",
            "manual" => true,
            "weight_kg" => 1000,
            "volume_l" => 1000
          }
        },
        "ports" => Map.new(["Singapore", "Colombo", "Dubai", "Tokyo"], &{&1, %{}}),
        "routes" => %{
          "Singapore|Colombo" => %{"nautical_miles" => 500, "passages" => []},
          "Singapore|Dubai" => %{"nautical_miles" => 900, "passages" => []}
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
        "buyer_budget" => 1_000_000,
        "handling_fee" => 10
      }
    end

    view = %{
      public: %{"clock_ms" => 0},
      private: %{
        "company" => %{"cash" => 1_000_000, "reserved" => 0, "unpaid" => 0},
        "ships" => %{}
      },
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
     %{
       "id" => "s1",
       "cargo" => [],
       "class" => "small_freighter",
       "status" => "docked",
       "port" => "Singapore"
     }}
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

  test "both directions cap lots by buyer cash and omit unaffordable opportunities" do
    {definitions, view, ship} = fixture()

    view =
      view
      |> put_in([:markets, "Colombo|a", "buyer_budget"], 599)
      |> put_in([:markets, "Singapore|b", "buyer_budget"], 539)

    row =
      Enum.find(
        GameQueries.destination_matrix(definitions, view, ship).rows,
        &(&1.port == "Colombo")
      )

    assert row.cells["a"].outbound.lots == 2
    assert row.cells["b"].inbound.lots == 2
    assert_in_delta row.cells["a"].outbound.roi, 80 / 110, 0.00001

    for budget <- [0, 179] do
      blocked =
        view
        |> put_in([:markets, "Colombo|a", "buyer_budget"], budget)
        |> put_in([:markets, "Singapore|b", "buyer_budget"], budget)

      row =
        Enum.find(
          GameQueries.destination_matrix(definitions, blocked, ship).rows,
          &(&1.port == "Colombo")
        )

      assert row.cells["a"].outbound == nil
      assert row.cells["b"].inbound == nil
      assert row.best < 0
    end
  end

  test "cash cap on aboard cargo uses only the saleable batches for proceeds and ROI" do
    {definitions, view, ship} = fixture()
    view = put_in(view, [:markets, "Colombo|a", "buyer_budget"], 2599)

    ship =
      Map.put(ship, "cargo", [
        %{"good" => "a", "quantity" => 10, "unit_cost" => 100},
        %{"good" => "a", "quantity" => 30, "unit_cost" => 200}
      ])

    row =
      Enum.find(
        GameQueries.destination_matrix(definitions, view, ship).rows,
        &(&1.port == "Colombo")
      )

    assert row.cells["a"].outbound.lots == 12
    assert row.cells["a"].outbound.proceeds == 2280
    assert_in_delta row.cells["a"].outbound.roi, 880 / 1400, 0.00001

    blocked = put_in(view, [:markets, "Colombo|a", "buyer_budget"], 199)

    row =
      Enum.find(
        GameQueries.destination_matrix(definitions, blocked, ship).rows,
        &(&1.port == "Colombo")
      )

    assert row.cells["a"].outbound == nil
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

  test "return opportunities do not affect next-voyage ranking" do
    {definitions, view, ship} = fixture()
    view = put_in(view, [:markets, "Dubai|b", "ask"], 50)
    [colombo, dubai] = GameQueries.destination_matrix(definitions, view, ship).rows
    assert colombo.port == "Colombo"
    assert dubai.port == "Dubai"
    assert dubai.cells["b"].inbound.roi > colombo.cells["b"].inbound.roi
    assert colombo.best > dubai.best
  end

  test "total dollars outrank percentage and mixed dry cargo shares the hold" do
    {definitions, view, ship} = fixture()

    view =
      view
      |> put_in([:markets, "Singapore|a", "stock"], 150)
      |> put_in([:markets, "Singapore|b", "stock"], 150)
      |> put_in([:markets, "Colombo|a", "demand"], 100)
      |> put_in([:markets, "Colombo|a", "bid"], 1100)
      |> put_in([:markets, "Colombo|b", "demand"], 150)
      |> put_in([:markets, "Colombo|b", "bid"], 1000)
      |> put_in([:markets, "Dubai|a", "demand"], 1)
      |> put_in([:markets, "Dubai|a", "bid"], 10_000)

    [colombo, dubai] = GameQueries.destination_matrix(definitions, view, ship).rows
    assert colombo.port == "Colombo"
    assert dubai.cells["a"].outbound.roi > colombo.cells["a"].outbound.roi
    assert colombo.plan.purchases == [%{good: "a", lots: 100}, %{good: "b", lots: 100}]
    assert colombo.plan.profit > dubai.plan.profit
    assert colombo.plan.costs > 0
  end

  test "aboard cargo shares destination buyer funds with extra purchases" do
    {definitions, view, ship} = fixture()
    ship = Map.put(ship, "cargo", [%{"good" => "a", "quantity" => 10, "unit_cost" => 100}])

    view =
      view
      |> put_in([:markets, "Colombo|a", "bid"], 1000)
      |> put_in([:markets, "Colombo|a", "buyer_budget"], 15_000)

    row =
      Enum.find(
        GameQueries.destination_matrix(definitions, view, ship).rows,
        &(&1.port == "Colombo")
      )

    assert row.plan.purchases == [%{good: "a", lots: 5}]
    assert row.plan.sales == [%{good: "a", lots: 15}]
  end

  test "purchases reserve voyage funding and queued orders suppress purchase suggestions" do
    {definitions, view, ship} = fixture()

    view =
      view
      |> put_in([:private, "company", "cash"], 6000)
      |> put_in([:markets, "Colombo|a", "bid"], 1000)

    row =
      Enum.find(
        GameQueries.destination_matrix(definitions, view, ship).rows,
        &(&1.port == "Colombo")
      )

    assert row.plan.spent + row.plan.costs <= 6000
    assert hd(row.plan.purchases).lots < 20
    queued = Map.put(ship, "pending_side", "buy")

    row =
      Enum.find(
        GameQueries.destination_matrix(definitions, view, queued).rows,
        &(&1.port == "Colombo")
      )

    assert row.plan.purchases == []
    broke = put_in(view, [:private, "company", "cash"], 0)

    assert Enum.all?(
             GameQueries.destination_matrix(definitions, broke, ship).rows,
             &is_nil(&1.plan)
           )
  end

  test "volume limits a mix and liquid holds never mix commodities" do
    {definitions, view, ship} = fixture()
    definitions = put_in(definitions, [:catalogue, "goods", "a", "volume_l"], 100_000)
    view = put_in(view, [:markets, "Colombo|a", "bid"], 10_000)
    row = hd(GameQueries.destination_matrix(definitions, view, ship).rows)
    assert row.plan.purchases == [%{good: "a", lots: 4}]

    definitions =
      update_in(definitions, [:catalogue, "goods"], fn goods ->
        Map.new(goods, fn {id, item} -> {id, Map.put(item, "hold", "liquid")} end)
      end)

    view =
      view
      |> put_in([:markets, "Singapore|b", "stock"], 100)
      |> put_in([:markets, "Colombo|b", "demand"], 100)
      |> put_in([:markets, "Colombo|b", "bid"], 1000)

    tanker = %{ship | "class" => "tanker"}
    row = hd(GameQueries.destination_matrix(definitions, view, tanker).rows)
    assert length(row.plan.purchases) == 1
    assert length(row.plan.sales) == 1
  end

  test "canal fees reduce profit, maintenance only affects funding, and known spoilage is a loss" do
    {definitions, view, ship} = fixture()

    estimate = fn defs, v, s ->
      Enum.find(GameQueries.destination_matrix(defs, v, s).rows, &(&1.port == "Colombo")).plan
    end

    original = estimate.(definitions, view, ship)
    canal = put_in(definitions, [:catalogue, "routes", "Singapore|Colombo", "passages"], ["suez"])
    assert estimate.(canal, view, ship).profit == original.profit - 25_000
    old_view = put_in(view, [:public, "clock_ms"], 60 * 86_400_000)

    assert estimate.(definitions, old_view, Map.put(ship, "built_ms", 0)).profit ==
             original.profit

    tight = put_in(old_view, [:private, "company", "cash"], 5000)
    assert estimate.(definitions, tight, Map.put(ship, "built_ms", 0)) == nil

    view = put_in(view, [:markets, "Singapore|a", "stock"], 0)
    cargo = %{"good" => "a", "quantity" => 10, "unit_cost" => 100, "expires_ms" => 1}
    expired = estimate.(definitions, view, Map.put(ship, "cargo", [cargo]))
    assert expired.sales == []
    assert expired.profit == -1000 - expired.costs
  end

  test "tankers rank combined profit with a funded onward load and cleaning" do
    {definitions, view, ship} = fixture()

    definitions =
      update_in(definitions, [:catalogue, "goods"], fn goods ->
        Map.new(goods, fn {id, item} -> {id, Map.put(item, "hold", "liquid")} end)
      end)

    definitions =
      put_in(definitions, [:catalogue, "routes", "Dubai|Tokyo"], %{
        "nautical_miles" => 100,
        "passages" => []
      })

    ship =
      Map.merge(ship, %{
        "class" => "tanker",
        "last_liquid" => "a",
        "cargo" => [%{"good" => "a", "quantity" => 10, "unit_cost" => 100}]
      })

    view =
      view
      |> put_in([:markets, "Singapore|a", "stock"], 0)
      |> put_in([:markets, "Dubai|a", "bid"], 1000)
      |> put_in([:markets, "Colombo|a", "bid"], 1100)
      |> put_in([:markets, "Dubai|b", "stock"], 100)
      |> put_in([:markets, "Dubai|b", "ask"], 100)

    buyer = %{view.markets["Dubai|b"] | "stock" => 0, "demand" => 100, "bid" => 2000}
    view = put_in(view, [:markets, "Tokyo|b"], buyer)
    [dubai, colombo] = GameQueries.destination_matrix(definitions, view, ship).rows
    assert dubai.port == "Dubai"
    assert dubai.plan.profit < colombo.plan.profit
    assert dubai.plan.onward.destination == "Tokyo"
    assert dubai.plan.onward.purchases == [%{good: "b", lots: 100}]
    assert dubai.plan.onward.spent == 16_000
    assert dubai.best == dubai.plan.profit + dubai.plan.onward.profit
    assert colombo.plan.onward == nil

    html =
      render_component(&DestinationPicker.panel/1,
        definitions: definitions,
        view: view,
        ship: ship
      )

    assert html =~ "Two voyages"
    assert html =~ "Then sail to Tokyo"

    limited = put_in(view, [:private, "company", "cash"], 9000)

    row =
      Enum.find(
        GameQueries.destination_matrix(definitions, limited, ship).rows,
        &(&1.port == "Dubai")
      )

    assert row.plan.onward != nil
    assert hd(row.plan.onward.purchases).lots in 1..99
    assert row.plan.onward.remaining_cash >= 0

    # A partial sale must not pretend the tank is empty and load a different liquid.
    view = put_in(view, [:markets, "Dubai|a", "demand"], 5)

    row =
      Enum.find(
        GameQueries.destination_matrix(definitions, view, ship).rows,
        &(&1.port == "Dubai")
      )

    assert row.plan.onward == nil
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
