defmodule TijaraTides.Domain.AuctionRootTest do
  use ExUnit.Case, async: true
  alias TijaraTides.Domain.{Auction, AuctionWorld, ChangeSet}
  alias TijaraTides.Domain.Auction.{Admission, Bid, BidRows, Rows, Transition}

  defp lot do
    %Auction{
      id: "lot",
      company_id: "seller",
      warehouse_id: "storage",
      port: "port",
      good: "art",
      quantity: 3,
      reserve: 100,
      opens_ms: 10,
      closes_ms: 20,
      status: "scheduled",
      price: nil,
      winner_id: nil,
      valuation_seed: "seed"
    }
  end

  defp context(overrides \\ []),
    do:
      struct!(
        Admission,
        Keyword.merge(
          [clock_ms: 10, revision: 1, company_bid_count: 0, id_taken?: false],
          overrides
        )
      )

  test "scheduling consumes explicit timing settings without a catalogue" do
    assert Auction.schedule(0, 3, 10, 5) == {3, 8}
    assert Auction.schedule(3, 3, 10, 5) == {13, 18}
    assert Auction.schedule(23, 3, 10, 5) == {33, 38}
  end

  test "a complete bidding lifecycle uses only the typed root and supplied facts" do
    auction = Auction.list(lot(), 0)
    {:ok, bid} = Auction.prepare_bid(auction, "buyer", "store", 200, "bid", context())

    %Transition{auction: accepted, bids_to_record: [^bid], bids_to_remove: []} =
      Auction.accept_bid(auction, bid, context())

    assert Auction.bid(accepted, "buyer") == bid
    assert Auction.bids(auction) == []

    next_context = context(clock_ms: 11, revision: 2, company_bid_count: 1, id_taken?: true)
    {:ok, raised} = Auction.prepare_bid(accepted, "buyer", "store", 300, "request", next_context)

    %Transition{auction: replaced, bids_to_record: [^raised], bids_to_remove: []} =
      Auction.replace_bid(accepted, bid, raised, next_context)

    assert Auction.bid(replaced, "buyer").priority_ms == 11
    assert_raise ArgumentError, fn -> Auction.replace_bid(replaced, bid, raised, next_context) end

    %Transition{auction: withdrawn, bids_to_record: [], bids_to_remove: [^raised]} =
      Auction.withdraw_bid(replaced, raised, 12)

    assert Auction.bids(withdrawn) == []
    assert Auction.bid(replaced, "buyer") == raised
    assert Auction.close_unsold(withdrawn, 20).status == "unsold"
  end

  test "acceptance rechecks external admission facts without exempting stale preparations" do
    {:ok, bid} = Auction.prepare_bid(lot(), "buyer", "store", 200, "bid", context())

    for blocked <- [
          context(company_bid_count: 100),
          context(id_taken?: true),
          context(clock_ms: 20)
        ] do
      assert_raise ArgumentError, fn -> Auction.accept_bid(lot(), bid, blocked) end
    end

    %Transition{auction: accepted} = Auction.accept_bid(lot(), bid, context())

    {:ok, replacement} =
      Auction.prepare_bid(accepted, "buyer", "store", 300, "request", context())

    assert %Transition{} =
             Auction.replace_bid(
               accepted,
               bid,
               replacement,
               context(company_bid_count: 100, id_taken?: true)
             )
  end

  test "simulated transitions reject global identifier collisions and preserve typed children" do
    simulated = Bid.simulated(lot(), 1, 200)

    assert_raise ArgumentError, fn ->
      Auction.record_simulated_bids(lot(), [simulated], 20, MapSet.new([simulated.id]))
    end

    %Transition{auction: recorded, bids_to_record: [^simulated]} =
      Auction.record_simulated_bids(lot(), [simulated], 20, MapSet.new())

    sold = Auction.close_sold(recorded, 100, simulated, 20)
    assert sold.status == "sold"
    assert Auction.bids(sold) == [simulated]
  end

  test "auction codec preserves every durable field but never encodes children" do
    auction = lot()
    row = Rows.encode(auction)
    assert Rows.decode(row) == auction
    {:ok, bid} = Auction.prepare_bid(auction, "buyer", "store", 200, "bid", context())
    %Transition{auction: accepted} = Auction.accept_bid(auction, bid, context())
    assert Rows.encode(accepted) == row

    for key <- Map.keys(row) do
      assert_raise ArgumentError, fn -> Rows.decode(Map.delete(row, key)) end
    end

    assert_raise ArgumentError, fn -> Rows.decode(Map.put(row, "unmapped", 1)) end
  end

  test "world integration tracks explicit child changes and preserves unrelated and historical rows" do
    initial = %{entities: %{}, clock_ms: 0, revision: 1}
    state = initial |> AuctionWorld.list(lot()) |> AuctionWorld.list(%{lot() | id: "other"})
    state = %{state | clock_ms: 10}
    {:ok, one} = AuctionWorld.prepare_bid(state, "lot", "buyer", "store", 200, "one")
    {:ok, two} = AuctionWorld.prepare_bid(state, "other", "buyer", "store", 200, "two")
    accepted = state |> AuctionWorld.accept_bid(one) |> AuctionWorld.accept_bid(two)
    assert AuctionWorld.fetch(accepted, "lot").bids == %{one.id => one}

    assert ChangeSet.since(state, accepted) == %{
             {"auction_bids", "one"} => :put,
             {"auction_bids", "two"} => :put
           }

    withdrawn = AuctionWorld.withdraw_bid(accepted, one)
    assert ChangeSet.since(accepted, withdrawn) == %{{"auction_bids", "one"} => :delete}
    assert AuctionWorld.bid(withdrawn, "other", "buyer") == two
    closed = AuctionWorld.close_unsold(%{withdrawn | clock_ms: 20}, "other")
    assert ChangeSet.since(withdrawn, closed) == %{{"auctions", "other"} => :put}
    assert closed.entities["auction_bids"]["two"] == BidRows.encode(two)
    assert AuctionWorld.fetch(closed, "other").bids == %{two.id => two}
  end
end
