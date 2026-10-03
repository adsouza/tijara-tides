defmodule TijaraTides.UseCases.MarketOffersTest do
  # Market offers use the commands' stock and receiving capacity rules.
  # Exact boundaries are accepted; one more lot and fully claimed space are refused.
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias TijaraTides.Domain.{CargoLots, CompanyFinanceWorld, Game, Markets, State}
  alias TijaraTides.Domain.{Auction, AuctionWorld, Visibility, Warehouse, WarehouseWorld}
  alias TijaraTides.Domain.Services.{Auctions, Exchange}
  alias TijaraTides.Domain.Ship.CargoRows
  alias TijaraTides.UseCases.GameQueries

  setup do
    definitions = TijaraTides.UseCases.Game.definitions()
    cat = definitions.catalogue
    s = Game.initialize(%{entities: %{}, clock_ms: 0, epoch: 1, revision: 0}, cat)
    {:ok, s, _} = Game.seed_invite(s, "invite")
    {:ok, s, _} = Game.redeem(s, "invite", "session", %{id: "a", wall_ms: 0})

    {:ok, s, _} =
      TijaraTides.CompanyFixture.create_company(
        s,
        Game.get(s, "accounts", "a"),
        "a",
        "Jakarta",
        "general",
        %{id: "aco", catalogue: cat}
      )

    %{s: s, definitions: definitions, cat: cat}
  end

  # Leases dry storage for `days` and stocks it with `quantity` lots of `good`.
  defp stocked(c, good, quantity, days) do
    {:ok, s, _} =
      WarehouseWorld.lease(
        c.s,
        account(c.s),
        %{
          "port" => "Jakarta",
          "storage" => "dry",
          "blocks" => 10,
          "days" => days,
          "price" => Warehouse.quote(WarehouseWorld.used(c.s, "Jakarta", "dry"), "dry", 10, days)
        },
        "aw",
        c.cat
      )

    {s, lot} = CargoLots.create(s, good, quantity, nil)
    row = Game.get(s, "warehouses", "aw")

    batch =
      CargoRows.encode(
        CargoRows.decode(
          Map.merge(lot, %{"good" => good, "unit_cost" => 100, "expires_ms" => nil})
        )
      )

    s
    |> State.put("warehouses", "aw", %{row | "cargo" => [batch]})
    |> CompanyFinanceWorld.post("aco", "purchase", [
      {"inventory", 100 * quantity},
      {"cash_available", -100 * quantity}
    ])
  end

  defp account(s), do: Game.get(s, "accounts", "a")

  defp view(s, cat),
    do: %{
      public: Visibility.public(s, cat),
      private: Visibility.private(s, account(s)),
      markets: Markets.quotes(s, cat)
    }

  defp sell(s, cat, n),
    do:
      Exchange.place(
        s,
        account(s),
        %{
          "warehouse" => "aw",
          "good" => "lumber",
          "side" => "sell",
          "quantity" => n,
          "price" => 1_000_000
        },
        "order-#{n}",
        cat
      )

  defp consign(s, cat, n),
    do:
      Auctions.consign(
        s,
        account(s),
        %{"warehouse" => "aw", "good" => "whisky", "quantity" => n, "price" => 1_000_000},
        "consign-#{n}",
        cat,
        "seed"
      )

  defp reserve(s, cat, quantity),
    do:
      WarehouseWorld.reserve(
        s,
        account(s),
        %{
          "warehouse" => "aw",
          "ship" => "aco:1",
          "good" => "lumber",
          "kind" => "capacity",
          "quantity" => quantity
        },
        "capacity",
        cat
      )

  defp buy(s, cat, quantity, id \\ "buy"),
    do:
      Exchange.place(
        s,
        account(s),
        %{
          "warehouse" => "aw",
          "good" => "lumber",
          "side" => "buy",
          "quantity" => quantity,
          "price" => 1
        },
        id,
        cat
      )

  defp listing(s, quantity, id \\ "world-whisky") do
    AuctionWorld.list(s, %Auction{
      id: id,
      company_id: nil,
      warehouse_id: nil,
      port: "Jakarta",
      good: "whisky",
      quantity: quantity,
      reserve: 100,
      opens_ms: s.clock_ms + 1,
      closes_ms: s.clock_ms + 10_000,
      status: "scheduled",
      price: nil,
      winner_id: nil,
      valuation_seed: "probe"
    })
  end

  defp bid(s, cat, warehouse \\ "aw", price \\ 100, auction \\ "world-whisky"),
    do:
      Auctions.bid(
        s,
        account(s),
        %{"auction" => auction, "warehouse" => warehouse, "price" => price},
        "bid-#{auction}-#{price}",
        cat
      )

  defp bid_storage(c, s, auction \\ "world-whisky") do
    GameQueries.auction_options(c.definitions, view(s, c.cat), "Jakarta").listings
    |> Enum.find(&(&1["id"] == auction))
    |> Map.fetch!("warehouses")
    |> Enum.map(& &1["id"])
  end

  defp exchange_form(c, s) do
    html =
      render_component(&TijaraTidesWeb.GameUI.ExchangePanel.panel/1,
        definitions: c.definitions,
        view: view(s, c.cat),
        port: "Jakarta",
        good: "lumber",
        request_id: "probe"
      )

    id = "exchange-place-" <> Base.url_encode64("Jakarta|lumber|buy", padding: false)
    html |> LazyHTML.from_fragment() |> LazyHTML.query("form[id='#{id}']") |> Enum.to_list()
  end

  defp auction_form(c, s, id) do
    render_component(&TijaraTidesWeb.GameUI.AuctionPanel.panel/1,
      definitions: c.definitions,
      view: view(s, c.cat),
      port: "Jakarta",
      request_id: "probe"
    )
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("form[id='auction-bid-#{id}']")
    |> Enum.to_list()
  end

  test "exchange buy offers require at least one unclaimed lot of receiving space", c do
    s = stocked(c, "lumber", 1, 3)
    {:ok, s, _} = reserve(s, c.cat, 623)
    # One million litres minus 624 lumber lots leaves exactly one more lumber lot.
    assert [%{"id" => "aw"}] =
             GameQueries.exchange_options(c.definitions, view(s, c.cat), "Jakarta", "lumber").buy_warehouses

    assert [_form] = exchange_form(c, s)
    assert {:ok, full, _} = buy(s, c.cat, 1)
    assert {:error, :warehouse_capacity} = buy(s, c.cat, 2)

    assert GameQueries.exchange_options(c.definitions, view(full, c.cat), "Jakarta", "lumber").buy_warehouses ==
             []

    assert exchange_form(c, full) == []
    assert {:error, :warehouse_capacity} = buy(full, c.cat, 1, "second-buy")
  end

  test "auction offers require space for the entire lot and preserve replacement space", c do
    s = stocked(c, "lumber", 1, 3)
    {:ok, s, _} = reserve(s, c.cat, 623)
    # The remaining 1,600 litres holds exactly 32 whisky lots at 50 litres each.
    s = s |> listing(32) |> listing(33, "too-large") |> listing(1, "another")
    s = %{s | clock_ms: 1}
    assert bid_storage(c, s) == ["aw"]
    assert bid_storage(c, s, "too-large") == []
    assert [_form] = auction_form(c, s, "world-whisky")
    assert auction_form(c, s, "too-large") == []
    assert {:error, :warehouse_capacity} = bid(s, c.cat, "aw", 100, "too-large")
    assert {:ok, full, _} = bid(s, c.cat)
    assert bid_storage(c, full) == ["aw"]
    assert [_form] = auction_form(c, full, "world-whisky")
    assert {:ok, _, _} = bid(full, c.cat, "aw", 101)
    assert bid_storage(c, full, "another") == []
    assert {:error, :warehouse_capacity} = bid(full, c.cat, "aw", 100, "another")
  end

  test "won cargo in shared allocations consumes market receiving space", c do
    s = stocked(c, "lumber", 625, 3)
    cargo = Game.get(s, "warehouses", "aw")["cargo"]
    s = s |> WarehouseWorld.award_storage("aw", "won", cargo, c.cat) |> listing(1)
    s = %{s | clock_ms: 1}
    assert Game.get(s, "warehouses", "aw")["cargo"] == []

    assert GameQueries.exchange_options(c.definitions, view(s, c.cat), "Jakarta", "lumber").buy_warehouses ==
             []

    assert {:error, :warehouse_capacity} = buy(s, c.cat, 1)
    assert bid_storage(c, s) == []
    assert {:error, :warehouse_capacity} = bid(s, c.cat)
  end

  test "a warehouse is offered for sell orders exactly while it holds claimable stock", c do
    s = stocked(c, "lumber", 10, 1)
    book = GameQueries.exchange_options(c.definitions, view(s, c.cat), "Jakarta", "lumber")
    assert Enum.map(book.sell_warehouses, & &1["id"]) == ["aw"]

    assert {:ok, reserved, _} = sell(s, c.cat, 10)
    assert {:error, :insufficient_cargo} = sell(s, c.cat, 11)

    # Once every lot backs an order, the warehouse is no longer offered and selling fails.
    book = GameQueries.exchange_options(c.definitions, view(reserved, c.cat), "Jakarta", "lumber")
    assert book.sell_warehouses == []
    assert {:error, :insufficient_cargo} = sell(reserved, c.cat, 1)
  end

  test "a consignment offer carries the claimable quantity the command accepts", c do
    s = stocked(c, "whisky", 3, 3)

    assert [%{good: "whisky", quantity: 3} = offer] =
             GameQueries.auction_options(c.definitions, view(s, c.cat), "Jakarta").consignable

    assert offer.warehouse["id"] == "aw"
    assert {:ok, consigned, _} = consign(s, c.cat, 3)
    assert {:error, :insufficient_cargo} = consign(s, c.cat, 4)

    # Consigned lots are reserved, so nothing more is offered or accepted.
    assert GameQueries.auction_options(c.definitions, view(consigned, c.cat), "Jakarta").consignable ==
             []

    assert {:error, :insufficient_cargo} = consign(consigned, c.cat, 1)
  end

  test "storage that ends before the next auction closes offers no consignment", c do
    s = stocked(c, "whisky", 3, 1)
    {_opens, closes} = TijaraTides.Domain.AuctionWorld.schedule(0, "Jakarta", c.cat)
    lease = WarehouseWorld.snapshot(Game.get(s, "warehouses", "aw"))
    refute Warehouse.covers?(lease, closes, 0)

    assert GameQueries.auction_options(c.definitions, view(s, c.cat), "Jakarta").consignable == []
    assert {:error, {:auction_storage, _, _}} = consign(s, c.cat, 1)
  end
end
