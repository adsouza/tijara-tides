defmodule TijaraTidesWeb.AuctionDiscoveryTest do
  use ExUnit.Case, async: true

  defp definitions, do: TijaraTides.UseCases.Game.definitions()
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
      |> TijaraTides.Domain.Warehouse.Rows.encode()

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

  test "discovery keeps older own sales, unsold consignments and bids beyond the global limit" do
    listings =
      for n <- 1..24,
          do: %{
            "id" => to_string(n),
            "port" => "Port #{n}",
            "good" => "jewelry",
            "closes_ms" => n,
            "status" => if(n == 2, do: "unsold", else: "sold")
          }

    view = %{
      public: %{"clock_ms" => 100, "auctions" => listings},
      private: %{
        "consignments" => Enum.take(listings, 2),
        "auction_bids" => [%{"auction_id" => "3", "won" => true}]
      }
    }

    ids =
      GameQueries.auction_discovery(view, "status", true)
      |> Enum.flat_map(&elem(&1, 1))
      |> Enum.map(& &1["id"])

    own = GameQueries.auction_discovery(view, "status") |> Enum.flat_map(&elem(&1, 1))
    assert Enum.map(own, & &1["id"]) == ["3", "2", "1"]
    assert length(ids) == 23
    assert Enum.all?(["1", "2", "3"], &(&1 in ids))
    refute "4" in ids
    assert GameQueries.auction_discovery(view, "cargo", true) == []
  end

  test "reserve revisions use whole dollars while preserving unchanged legacy cents" do
    for {reserve, value, exact} <- [{1000, "10", "10.00"}, {1001, "", "10.01"}] do
      lot = %{
        "id" => "own",
        "good" => "jewelry",
        "port" => "Dubai",
        "quantity" => 2,
        "reserve" => reserve,
        "status" => "scheduled",
        "opens_ms" => 2000,
        "closes_ms" => 3000,
        "price" => nil,
        "amounts" => []
      }

      html =
        render_component(&AuctionPanel.panel/1,
          definitions: TijaraTides.UseCases.Game.definitions(),
          port: "Dubai",
          request_id: "test",
          view: %{
            public: %{"clock_ms" => 1000, "auctions" => [lot]},
            private: %{"consignments" => [lot]}
          }
        )

      tree = LazyHTML.from_fragment(html)
      input = LazyHTML.query(tree, "#auction-own input[name=reserve_dollars]")
      assert LazyHTML.attribute(input, "min") == ["1"]
      assert LazyHTML.attribute(input, "step") == ["1"]
      assert LazyHTML.attribute(input, "value") == [value]

      assert LazyHTML.query(tree, "#auction-own input[name=price]") |> LazyHTML.attribute("value") ==
               [exact]

      if reserve == 1001, do: assert(html =~ "Leave blank to keep the existing reserve.")
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
          Map.merge(lot, %{"id" => "sold", "status" => "sold", "price" => 2_500_000}),
          Map.merge(lot, %{"id" => "expired", "closes_ms" => 1000})
        ]
      }
    }

    view =
      Map.put(view, :private, %{"auction_bids" => [%{"auction_id" => "sold", "won" => true}]})

    assert [{"jewelry", [first, second]}] = GameQueries.auction_discovery(view, "cargo")

    assert [{"open", [_]}, {"upcoming", [_]}, {"settled", [_]}] =
             GameQueries.auction_discovery(view)

    assert first["id"] == "open"
    assert second["id"] == "upcoming"
    html = render_component(&AuctionPanel.discovery/1, view: view, definitions: definitions())
    tree = LazyHTML.from_fragment(html)

    assert LazyHTML.query(tree, "#discover-auctions-status-open[open]") |> LazyHTML.to_html() !=
             ""

    assert LazyHTML.query(tree, "#discover-auctions-status-upcoming[open]") |> LazyHTML.to_html() ==
             ""

    assert html =~ "Open auctions"

    cargo_html =
      render_component(&AuctionPanel.discovery/1,
        view: view,
        definitions: definitions(),
        grouping: "cargo"
      )

    assert cargo_html =~ "discover-auctions-cargo-jewelry"
    refute cargo_html =~ "Open auctions"
    refute cargo_html =~ "auction-settled-filter"
    refute cargo_html =~ "data-auction=\"sold\""
    refute html =~ "Bidding open"
    assert html =~ "Closes in"
    assert cargo_html =~ "Bidding open"
    assert html =~ "Opens in"
    assert html =~ "auction-port"
    assert html =~ "data-auction=\"sold\""
    assert html =~ "Settled auctions"
    assert html =~ "You won"
    assert html =~ "$25,000"
    settled_row = LazyHTML.query(tree, "[data-auction=sold]") |> LazyHTML.text()
    refute settled_row =~ "Closes in"
    refute html =~ "data-auction=\"expired\""
    assert html =~ "ignore_attrs"
  end

  test "settled discovery expires after three active-world days, including own auctions" do
    day = 86_400_000
    clock = 5 * day

    lot = %{
      "good" => "jewelry",
      "port" => "Dubai",
      "quantity" => 1,
      "reserve" => 100,
      "status" => "sold",
      "opens_ms" => 0
    }

    auction = fn id, closes -> Map.merge(lot, %{"id" => id, "closes_ms" => closes}) end

    view = %{
      public: %{
        "clock_ms" => clock,
        "auctions" => [
          auction.("recent", clock - day),
          auction.("boundary", clock - 3 * day),
          auction.("old-win", clock - 3 * day - 1),
          auction.("old-consignment", clock - 4 * day),
          Map.merge(auction.("upcoming", clock + day), %{
            "status" => "scheduled",
            "opens_ms" => clock + 1000
          })
        ]
      },
      private: %{
        "auction_bids" => [%{"auction_id" => "old-win", "won" => true}],
        "consignments" => [%{"id" => "old-consignment"}]
      }
    }

    assert [{"upcoming", [_]}, {"settled", settled}] =
             GameQueries.auction_discovery(view, "status", true)

    assert Enum.map(settled, & &1["id"]) == ["recent", "boundary"]
    assert [{"jewelry", listings}] = GameQueries.auction_discovery(view, "cargo", true)
    assert Enum.map(listings, & &1["id"]) == ["upcoming"]
    assert [{"upcoming", [_]}] = GameQueries.auction_discovery(view)

    participating =
      put_in(view, [:private, "auction_bids"], [%{"auction_id" => "recent", "won" => false}])

    participating = put_in(participating, [:private, "consignments"], [%{"id" => "boundary"}])
    assert [{"upcoming", [_]}, {"settled", own}] = GameQueries.auction_discovery(participating)
    assert Enum.map(own, & &1["id"]) == ["recent", "boundary"]
    later = put_in(view, [:public, "clock_ms"], clock + 1)

    assert [{"upcoming", [_]}, {"settled", [remaining]}] =
             GameQueries.auction_discovery(later, "status", true)

    assert remaining["id"] == "recent"
  end

  test "settled filter stays inside its section even without participating auctions" do
    html = render_component(&AuctionPanel.discovery/1, view: %{}, definitions: definitions())
    tree = LazyHTML.from_fragment(html)

    assert LazyHTML.query(tree, "#discover-auctions-status-settled #auction-settled-filter")
           |> LazyHTML.to_html() != ""

    assert LazyHTML.query(tree, "#auction-discovery > #auction-settled-filter")
           |> LazyHTML.to_html() == ""
  end

  test "empty discovery works without a public snapshot" do
    assert render_component(&AuctionPanel.discovery/1, view: %{}, definitions: definitions()) =~
             "No luxury auctions available."
  end
end
