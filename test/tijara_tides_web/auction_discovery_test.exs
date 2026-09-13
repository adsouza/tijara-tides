defmodule TijaraTidesWeb.AuctionDiscoveryTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest
  alias TijaraTides.UseCases.GameQueries
  alias TijaraTidesWeb.GameUI.AuctionPanel

  test "maximum bids use whole dollars rounded up to cover reserves and existing bids" do
    warehouse =
      %TijaraTides.Domain.Warehouse{
        id: "w",
        company_id: "buyer",
        port: "Dubai",
        storage: "dry",
        good: nil,
        blocks: 1,
        started_ms: 0,
        expires_ms: 10000,
        rent: 0,
        prepaid: 0,
        protected_ms: 0
      }
      |> TijaraTides.Domain.Warehouse.to_row()

    lot = %{
      "id" => "lot",
      "good" => "jewelry",
      "port" => "Dubai",
      "quantity" => 5,
      "reserve" => 2_500_001,
      "status" => "scheduled",
      "opens_ms" => 0,
      "closes_ms" => 3000,
      "price" => nil,
      "amounts" => []
    }

    for {bids, expected} <- [
          {[], "25001"},
          {[%{"auction_id" => "lot", "amount" => 3_000_005, "warehouse_id" => "w"}], "30001"}
        ] do
      html =
        render_component(&AuctionPanel.panel/1,
          definitions: TijaraTides.UseCases.Game.definitions(),
          port: "Dubai",
          request_id: "test",
          view: %{
            public: %{"clock_ms" => 1000, "auctions" => [lot]},
            private: %{"warehouses" => %{"w" => warehouse}, "auction_bids" => bids}
          }
        )

      input =
        html |> LazyHTML.from_fragment() |> LazyHTML.query("#auction-lot input[name=price][min]")

      assert html =~ "Dubai Ordinary storage 1"
      assert LazyHTML.attribute(input, "value") == [expected]
      assert LazyHTML.attribute(input, "step") == ["1"]
      assert LazyHTML.attribute(input, "min") == ["25001"]
    end
  end

  test "discovery groups live auctions and puts open bidding before upcoming lots" do
    lot = %{
      "good" => "jewelry",
      "port" => "Dubai",
      "quantity" => 5,
      "reserve" => 2_500_000,
      "status" => "scheduled",
      "opens_ms" => 0,
      "closes_ms" => 3000
    }

    view = %{
      public: %{
        "clock_ms" => 1000,
        "auctions" => [
          Map.merge(lot, %{"id" => "upcoming", "opens_ms" => 2000, "closes_ms" => 4000}),
          Map.put(lot, "id", "open"),
          Map.merge(lot, %{"id" => "sold", "status" => "sold"}),
          Map.merge(lot, %{"id" => "expired", "closes_ms" => 1000})
        ]
      }
    }

    assert [{"jewelry", [first, second]}] = GameQueries.auction_discovery(view, "cargo")
    assert [{"open", [_]}, {"upcoming", [_]}] = GameQueries.auction_discovery(view)
    assert first["id"] == "open"
    assert second["id"] == "upcoming"
    html = render_component(&AuctionPanel.discovery/1, view: view)
    tree = LazyHTML.from_fragment(html)

    assert LazyHTML.query(tree, "#discover-auctions-status-open[open]") |> LazyHTML.to_html() !=
             ""

    assert LazyHTML.query(tree, "#discover-auctions-status-upcoming[open]") |> LazyHTML.to_html() ==
             ""

    assert html =~ "Open auctions"
    cargo_html = render_component(&AuctionPanel.discovery/1, view: view, grouping: "cargo")
    assert cargo_html =~ "discover-auctions-cargo-jewelry"
    refute cargo_html =~ "Open auctions"
    assert html =~ "Bidding open"
    assert html =~ "Opens in"
    assert html =~ "auction-port"
    refute html =~ "data-auction=\"sold\""
    refute html =~ "data-auction=\"expired\""
    assert html =~ "ignore_attrs"
  end

  test "empty discovery works without a public snapshot" do
    assert render_component(&AuctionPanel.discovery/1, view: %{}) =~
             "No open or upcoming luxury auctions."
  end
end
