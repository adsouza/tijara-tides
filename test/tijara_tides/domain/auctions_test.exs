defmodule TijaraTides.Domain.AuctionsTest do
  use ExUnit.Case, async: true
  alias TijaraTides.Domain.{Game, State, Warehouse, CargoLots, CompanyFinance}
  alias TijaraTides.Domain.AuctionWorld, as: Auction
  alias TijaraTides.Domain.Services.Auctions

  setup do
    catalogue =
      TijaraTides.Infrastructure.GameCatalogue.all()
      |> Map.put("auctions", %{"interval_ms" => 10_000, "window_ms" => 10_000})

    state = Game.initialize(%{entities: %{}, clock_ms: 0, epoch: 1, revision: 0}, catalogue)
    {:ok, state, _} = Game.seed_invite(state, "invite")
    {:ok, state, _} = Game.redeem(state, "invite", "session", %{id: "a", wall_ms: 0})
    a = Game.get(state, "accounts", "a")
    state = State.put(state, "accounts", "b", %{a | "id" => "b"})
    state = State.put(state, "accounts", "c", %{a | "id" => "c"})

    state =
      Enum.reduce(["a", "b", "c"], state, fn id, s ->
        {:ok, s, _} =
          TijaraTides.CompanyFixture.create_company(
            s,
            Game.get(s, "accounts", id),
            id,
            "Jakarta",
            "general",
            %{id: id <> "co", catalogue: catalogue}
          )

        account = Game.get(s, "accounts", id)

        {:ok, s, _} =
          Warehouse.lease(
            s,
            account,
            %{
              "port" => "Jakarta",
              "storage" => "dry",
              "blocks" => 10,
              "days" => 1,
              "price" => Warehouse.quote(Warehouse.used(s, "Jakarta", "dry"), "dry", 10, 1)
            },
            id <> "w",
            catalogue
          )

        s
      end)

    # Isolate the player order book from NPC liquidity unless a test opts in.
    market = Game.get(state, "markets", "Jakarta|whisky")
    state = State.put(state, "markets", "Jakarta|whisky", %{market | "stock" => 0, "demand" => 0})

    %{
      state: state,
      catalogue: catalogue,
      a: Game.get(state, "accounts", "a"),
      b: Game.get(state, "accounts", "b"),
      c: Game.get(state, "accounts", "c")
    }
  end

  defp stock(c, state, owner, n) do
    {state, lot} = CargoLots.create(state, "whisky", n, nil)
    row = Game.get(state, "warehouses", owner <> "w")

    state =
      State.put(state, "warehouses", row["id"], %{
        row
        | "cargo" => row["cargo"] ++ [Map.merge(lot, %{"good" => "whisky", "unit_cost" => 100})]
      })

    CompanyFinance.post(state, c[String.to_existing_atom(owner)]["company_id"], "purchase", [
      {"inventory", n * 100},
      {"cash_available", -n * 100}
    ])
  end

  defp lot(c, s, n \\ 3) do
    s = stock(c, s, "a", n)

    {:ok, s, _} =
      Auctions.consign(
        s,
        c.a,
        %{"warehouse" => "aw", "good" => "whisky", "quantity" => n, "price" => 1000},
        "lot",
        c.catalogue,
        "seed"
      )

    s
  end

  defp bid(c, s, amount, id \\ "bid") do
    Auctions.bid(
      s,
      c.b,
      %{"auction" => "lot", "warehouse" => "bw", "price" => amount},
      id,
      c.catalogue
    )
  end

  test "sealed second-price sale releases escrow and preserves exact cost basis", c do
    s = lot(c, c.state)
    a = Auction.fetch(s, "lot")
    s = %{s | clock_ms: a.opens_ms}
    {:ok, s, _} = bid(c, s, 2001)
    assert hd(Enum.filter(Auction.public(s), &(&1["id"] == "lot")))["amounts"] == []
    assert Game.get(s, "companies", "bco")["reserved"] == 2001
    s = Auctions.advance(%{s | clock_ms: a.closes_ms}, c.catalogue)
    assert Auction.fetch(s, "lot").price == 1000
    assert Auction.fetch(s, "lot").status == "sold"
    assert Game.get(s, "companies", "bco")["reserved"] == 0
    cargo = Game.get(s, "warehouses", "bw")["cargo"]
    assert Enum.sum(for b <- cargo, do: b["quantity"]) == 3
    assert Enum.sum(for b <- cargo, do: b["quantity"] * b["unit_cost"]) == 1000
    assert Game.get(s, "warehouses", "aw")["cargo"] == []
    assert Game.get(s, "warehouse_reservations", "bid_id:bid") == nil
    assert Auctions.advance(s, c.catalogue).entities == s.entities
  end

  test "seller lock, exact close, revisions and withdrawal enforce boundaries", c do
    s = lot(c, c.state)
    a = Auction.fetch(s, "lot")
    assert {:error, :auction_invalid} = bid(c, s, 2000)

    assert {:ok, revised, _} =
             Auctions.revise(
               s,
               c.a,
               %{"auction" => "lot", "quantity" => 2, "price" => 999},
               c.catalogue
             )

    assert Auction.fetch(revised, "lot").quantity == 2
    s = %{s | clock_ms: a.opens_ms}
    assert {:error, :auction_locked} = Auctions.withdraw_lot(s, c.a, "lot")
    {:ok, s, _} = bid(c, s, 2000)
    {:ok, same, _} = bid(c, %{s | revision: 5}, 2000)
    assert Auction.bid(same, "lot", "bco").priority_seq == 0
    assert {:error, :insufficient_cash} = bid(c, s, 1_000_000_000_000)
    assert Auction.bid(s, "lot", "bco").amount == 2000
    {:ok, s, _} = bid(c, %{s | revision: 6}, 2001)
    assert Auction.bid(s, "lot", "bco").priority_seq == 6

    assert {:error, :auction_locked} =
             Auctions.withdraw_bid(%{s | clock_ms: a.closes_ms}, c.b, "lot")

    {:ok, s, _} = Auctions.withdraw_bid(s, c.b, "lot")
    assert Game.get(s, "companies", "bco")["reserved"] == 0
    assert Auction.bid(s, "lot", "bco") == nil
    s = Auctions.advance(%{s | clock_ms: a.closes_ms}, c.catalogue)
    assert Auction.fetch(s, "lot").status == "unsold"
  end

  test "storage coverage and seller stock cannot be bypassed", c do
    s = lot(c, c.state)
    a = Auction.fetch(s, "lot")
    s = %{s | clock_ms: a.opens_ms}
    w = Game.get(s, "warehouses", "bw")
    s = State.put(s, "warehouses", "bw", %{w | "expires_ms" => a.closes_ms - 1})
    assert {:error, :auction_storage} = bid(c, s, 2000)
    assert {:error, :warehouse_invalid} = Warehouse.cancel_reservation(s, c.a, "auction_id:lot")

    assert {:error, :insufficient_cargo} =
             Auctions.consign(
               s,
               c.a,
               %{"warehouse" => "aw", "good" => "whisky", "quantity" => 1, "price" => 100},
               "duplicate",
               c.catalogue,
               "seed"
             )
  end

  test "a seller bankruptcy cancels its auction and releases all bids", c do
    s = lot(c, c.state)
    a = Auction.fetch(s, "lot")
    {:ok, s, _} = bid(c, %{s | clock_ms: a.opens_ms}, 2000)
    company = Game.get(s, "companies", "aco")
    s = State.put(s, "companies", "aco", %{company | "bankruptcy_ms" => s.clock_ms})
    s = Auctions.advance(s, c.catalogue)
    assert Auction.fetch(s, "lot").status == "cancelled"
    assert Game.get(s, "companies", "bco")["reserved"] == 0
  end

  test "equal final amounts choose earliest acceptance and charge the tied price", c do
    s = lot(c, c.state)
    a = Auction.fetch(s, "lot")
    {:ok, s, _} = bid(c, %{s | clock_ms: a.opens_ms}, 2001)

    {:ok, s, _} =
      Auctions.bid(
        %{s | revision: 1},
        c.c,
        %{"auction" => "lot", "warehouse" => "cw", "price" => 2001},
        "second",
        c.catalogue
      )

    s = Auctions.advance(%{s | clock_ms: a.closes_ms}, c.catalogue)
    assert Auction.fetch(s, "lot").winner_id == "bco"
    assert Auction.fetch(s, "lot").price == 2001
    assert Game.get(s, "companies", "cco")["reserved"] == 0
    # The seller, winner and losing bidder must each retain their own notification.
    for account <- [c.a, c.b, c.c] do
      notices = TijaraTides.Domain.Visibility.private(s, account)["notices"]

      assert Enum.count(
               notices,
               &(&1["code"] == "auction.closed" and &1["arguments"]["port"] == a.port)
             ) == 1
    end

    [a] = Enum.filter(Auction.public(s), &(&1["id"] == "lot"))
    assert a["amounts"] == [2001, 2001]
    assert Auction.private_bids(s, nil) == []

    assert Enum.all?(
             TijaraTides.Domain.Visibility.private(s, c.a)["consignments"],
             &(not Map.has_key?(&1, "valuation_seed"))
           )

    refute Map.has_key?(a, "winner_id")
    refute Map.has_key?(a, "company_id")
  end

  test "simulated buyers compete within finite demand and budget", c do
    s = lot(c, c.state)
    a = Auction.fetch(s, "lot")
    m = Game.get(s, "markets", "Jakarta|whisky")

    s =
      State.put(s, "markets", "Jakarta|whisky", %{
        m
        | "buyer" => true,
          "demand" => 10,
          "budget" => 10_000_000
      })

    s = Auctions.advance(%{s | clock_ms: a.closes_ms}, c.catalogue)
    result = Auction.fetch(s, "lot")
    assert result.status == "sold"
    assert result.price > result.reserve
    assert Game.get(s, "markets", "Jakarta|whisky")["demand"] == 7
    assert Game.get(s, "markets", "Jakarta|whisky")["budget"] == 10_000_000 - result.price
  end

  test "computer supply makes luxury cargo available to acquire at an auction", c do
    s = Auctions.advance(c.state, c.catalogue)
    a = Enum.find(Auction.all(s), &(&1.company_id == nil and &1.good == "whisky"))
    assert a != nil
    # Use the bidder's warehouse at the listing port.
    w = Game.get(s, "warehouses", "bw")
    s = State.put(s, "warehouses", "bw", %{w | "port" => a.port})
    stock = Game.get(s, "markets", a.port <> "|whisky")["stock"]

    {:ok, s, _} =
      Auctions.bid(
        %{s | clock_ms: a.opens_ms},
        c.b,
        %{"auction" => a.id, "warehouse" => "bw", "price" => a.reserve},
        "npcbid",
        c.catalogue
      )

    s = Auctions.advance(%{s | clock_ms: a.closes_ms}, c.catalogue)
    assert Auction.fetch(s, a.id).status == "sold"
    assert Game.get(s, "markets", a.port <> "|whisky")["stock"] == stock - a.quantity

    assert Enum.sum(for b <- Game.get(s, "warehouses", "bw")["cargo"], do: b["quantity"]) ==
             a.quantity
  end

  test "schedule windows are independent and published listings survive configuration changes",
       c do
    s = lot(c, c.state)
    a = Auction.fetch(s, "lot")
    cat = Map.put(c.catalogue, "auctions", %{"interval_ms" => 1000, "window_ms" => 20_000})
    {open, close} = Auction.schedule(0, "Jakarta", cat)
    assert close - open == 20_000
    {next, _} = Auction.schedule(open, "Jakarta", cat)
    assert next - open == 1000
    assert Auction.fetch(Auctions.advance(s, cat), "lot").closes_ms == a.closes_ms
  end

  test "a tick crossing lease expiry settles bids covered through the exact close", c do
    s = lot(c, c.state)
    a = Auction.fetch(s, "lot")

    s =
      Enum.reduce(["aw", "bw"], s, fn id, s ->
        w = Game.get(s, "warehouses", id)
        State.put(s, "warehouses", id, %{w | "expires_ms" => a.closes_ms})
      end)

    {:ok, s, _} = bid(c, %{s | clock_ms: a.opens_ms}, 2000)
    s = Auctions.advance(%{s | clock_ms: a.closes_ms + 1000}, c.catalogue)
    assert Auction.fetch(s, "lot").status == "sold"
    assert Enum.sum(for b <- Game.get(s, "warehouses", "bw")["cargo"], do: b["quantity"]) == 3
  end

  test "supplier shortage closes unsold and releases every bidder's cash and space", c do
    s = Auctions.advance(c.state, c.catalogue)
    a = Enum.find(Auction.all(s), &(&1.company_id == nil and &1.good == "whisky"))
    balances = Map.new(["bco", "cco"], &{&1, Game.get(s, "companies", &1)["cash"]})

    s =
      Enum.reduce([{c.b, "bw"}, {c.c, "cw"}], %{s | clock_ms: a.opens_ms}, fn {account, id}, s ->
        w = Game.get(s, "warehouses", id)
        s = State.put(s, "warehouses", id, %{w | "port" => a.port})

        {:ok, s, _} =
          Auctions.bid(
            s,
            account,
            %{"auction" => a.id, "warehouse" => id, "price" => a.reserve + 100},
            "bid-" <> id,
            c.catalogue
          )

        s
      end)

    market = Game.get(s, "markets", a.port <> "|" <> a.good)

    {s, _cargo} =
      TijaraTides.Domain.PortCargoMarketWorld.release_stock(
        s,
        a.port,
        a.good,
        market["stock"] - a.quantity + 1,
        0,
        c.catalogue["goods"][a.good]
      )

    s = Auctions.advance(%{s | clock_ms: a.closes_ms}, c.catalogue)
    assert Auction.fetch(s, a.id).status == "unsold"
    assert Auction.fetch(s, a.id).price == nil

    for {company, warehouse} <- [{"bco", "bw"}, {"cco", "cw"}] do
      assert Game.get(s, "companies", company)["reserved"] == 0
      assert Game.get(s, "companies", company)["cash"] == balances[company]
      assert Game.get(s, "warehouse_reservations", "bid_id:bid-" <> warehouse) == nil
      assert Game.get(s, "warehouses", warehouse)["cargo"] == []
    end

    assert length(Auction.bids(s, a.id)) == 2
    again = Auctions.advance(s, c.catalogue)
    assert Game.entities(again, "companies") == Game.entities(s, "companies")
  end
end
