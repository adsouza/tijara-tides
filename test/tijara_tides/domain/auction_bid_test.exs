defmodule TijaraTides.Domain.AuctionBidTest do
  use ExUnit.Case, async: true
  alias TijaraTides.Domain.AuctionWorld, as: Auction
  alias TijaraTides.Domain.Auction, as: Lot
  alias TijaraTides.Domain.State
  alias TijaraTides.Domain.Auction.{Bid, BidRows}

  defp lot do
    %Lot{
      id: "lot",
      company_id: "seller",
      warehouse_id: "seller-store",
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

  defp opened do
    %{Auction.list(%{entities: %{}, clock_ms: 0, revision: 1}, lot()) | clock_ms: 10}
  end

  defp offer(state, amount \\ 200, id \\ "bid", company \\ "buyer") do
    Auction.prepare_bid(state, "lot", company, "store", amount, id)
  end

  test "ordinary bids obey opening, closing, reserve and seller exclusion without mutating state" do
    state = opened()

    for {clock, company, amount} <- [
          {9, "buyer", 200},
          {20, "buyer", 200},
          {10, "seller", 200},
          {10, "buyer", 99},
          {10, "buyer", 0},
          {10, "buyer", 200.0},
          {10, "buyer", 1_000_000_000_001}
        ] do
      assert {:error, :auction_invalid} =
               offer(%{state | clock_ms: clock}, amount, "bid", company)
    end

    assert {:error, :auction_invalid} =
             Auction.prepare_bid(state, "missing", "buyer", "store", 200, "bid")

    assert {:ok, %Bid{amount: 200}} = offer(state)
    assert Auction.bids(state, "lot") == []
    assert {:error, :auction_invalid} = offer(Auction.cancel(state, "lot"))
  end

  test "replacement preserves identity and unchanged-amount priority but rejects stale terms" do
    {:ok, original} = offer(opened())
    state = %{Auction.accept_bid(opened(), original) | clock_ms: 11, revision: 2}
    {:ok, moved} = Auction.prepare_bid(state, "lot", "buyer", "other-store", 200, "new-request")
    assert moved.id == original.id
    assert {moved.priority_ms, moved.priority_seq} == {10, 1}
    changed = Auction.replace_bid(state, original, moved)
    assert_raise ArgumentError, fn -> Auction.replace_bid(changed, original, moved) end
    assert_raise ArgumentError, fn -> Auction.accept_bid(state, moved) end

    {:ok, raised} = offer(changed, 300)
    assert {raised.priority_ms, raised.priority_seq} == {11, 2}

    assert_raise ArgumentError, fn ->
      Auction.replace_bid(changed, moved, %{raised | id: "other"})
    end

    replaced = Auction.replace_bid(changed, moved, raised)
    assert Auction.bid(replaced, "lot", "buyer") == raised
    assert_raise ArgumentError, fn -> Auction.withdraw_bid(replaced, original) end
    assert Auction.bids(Auction.withdraw_bid(replaced, raised), "lot") == []
  end

  test "acceptance revalidates the planned window and priority and refuses bid ID collisions" do
    state = opened()
    {:ok, bid} = offer(state)
    assert_raise ArgumentError, fn -> Auction.accept_bid(%{state | clock_ms: 20}, bid) end
    assert_raise ArgumentError, fn -> Auction.accept_bid(state, %{bid | priority_seq: 0}) end
    accepted = Auction.accept_bid(state, bid)
    assert {:error, :auction_invalid} = offer(accepted, 200, "bid", "other-buyer")
    {:ok, replacement} = offer(%{accepted | clock_ms: 11}, 300)

    assert_raise ArgumentError, fn ->
      Auction.replace_bid(%{accepted | clock_ms: 20}, bid, replacement)
    end
  end

  test "closing locks withdrawals but reconciliation can invalidate a current bid" do
    {:ok, bid} = offer(opened())
    due = %{Auction.accept_bid(opened(), bid) | clock_ms: 20}
    assert_raise ArgumentError, fn -> Auction.withdraw_bid(due, bid) end
    assert Auction.bids(Auction.invalidate_bid(due, bid), "lot") == []
    assert_raise ArgumentError, fn -> Auction.invalidate_bid(Auction.cancel(due, "lot"), bid) end
    assert_raise ArgumentError, fn -> Auction.invalidate_bid(due, %{bid | amount: 300}) end
  end

  test "simulated bids have a separate due-only path and cannot replace player bids" do
    state = opened()
    simulated = Bid.simulated(lot(), 1, 250)
    assert_raise ArgumentError, fn -> Auction.accept_bid(state, simulated) end
    assert_raise ArgumentError, fn -> Auction.record_simulated_bids(state, "lot", [simulated]) end
    due = %{state | clock_ms: 20}

    assert_raise ArgumentError, fn ->
      Auction.record_simulated_bids(due, "lot", [simulated, simulated])
    end

    for bad <- [
          %{simulated | company_id: "buyer", warehouse_id: "store"},
          %{simulated | id: "bid"},
          %{simulated | auction_id: "other"},
          %{simulated | amount: 99},
          %{simulated | priority_ms: 19}
        ] do
      assert_raise ArgumentError, fn -> Auction.record_simulated_bids(due, "lot", [bad]) end
    end

    recorded = Auction.record_simulated_bids(due, "lot", [simulated])
    assert Auction.bids(recorded, "lot") == [simulated]

    assert_raise ArgumentError, fn ->
      Auction.record_simulated_bids(recorded, "lot", [simulated])
    end

    sold = Auction.close_sold(recorded, "lot", 100, simulated)
    assert Auction.fetch(sold, "lot").status == "sold"
    assert_raise ArgumentError, fn -> Auction.record_simulated_bids(sold, "lot", []) end
    # Deliberately exercise the invalid input without a compile-time type warning.
    assert_raise ArgumentError, fn ->
      apply(Bid, :simulated, [%{lot() | company_id: nil}, 1, 200])
    end
  end

  test "bidder caps block new bids but allow replacement at capacity" do
    {:ok, bid} = offer(opened())

    full =
      Enum.reduce(1..1000, opened(), fn i, state ->
        b = %{bid | id: "bid-#{i}", company_id: "buyer-#{i}"}

        State.put(state, "auction_bids", b.id, BidRows.encode(b))
      end)

    assert {:error, :auction_invalid} = offer(full)
    assert {:ok, %Bid{id: "bid-1"} = replacement} = offer(full, 300, "request", "buyer-1")
    previous = Auction.bid(full, "lot", "buyer-1")
    replaced = Auction.replace_bid(full, previous, replacement)
    assert Auction.bid(replaced, "lot", "buyer-1") == replacement

    vacant = State.delete(full, "auction_bids", "bid-1000")
    {:ok, waiting} = offer(vacant)
    {:ok, last} = offer(vacant, 200, "bid-1000", "buyer-1000")
    filled = Auction.accept_bid(vacant, last)
    assert length(Auction.bids(filled, "lot")) == 1000
    assert_raise ArgumentError, fn -> Auction.accept_bid(filled, waiting) end

    company_full =
      Enum.reduce(1..100, opened(), fn i, state ->
        auction = %{lot() | id: "lot-#{i}"}
        b = %{bid | id: "bid-#{i}", auction_id: auction.id}

        state =
          State.put(
            state,
            "auctions",
            auction.id,
            TijaraTides.Domain.Auction.Rows.encode(auction)
          )

        State.put(state, "auction_bids", b.id, BidRows.encode(b))
      end)

    assert {:error, :auction_invalid} = offer(company_full)

    assert {:ok, replacement} =
             Auction.prepare_bid(company_full, "lot-1", "buyer", "store", 300, "request")

    previous = Auction.bid(company_full, "lot-1", "buyer")
    replaced = Auction.replace_bid(company_full, previous, replacement)
    assert Auction.bid(replaced, "lot-1", "buyer") == replacement

    vacant = State.delete(company_full, "auction_bids", "bid-100")
    {:ok, waiting} = offer(vacant)
    {:ok, last} = Auction.prepare_bid(vacant, "lot-100", "buyer", "store", 200, "bid-100")
    filled = Auction.accept_bid(vacant, last)
    assert length(Auction.company_bids(filled, "buyer")) == 100
    assert_raise ArgumentError, fn -> Auction.accept_bid(filled, waiting) end
  end

  test "codec preserves player and simulated rows and rejects silently discarded fields" do
    {:ok, player} = offer(opened())

    for bid <- [player, Bid.simulated(lot(), 1, 250)] do
      row = BidRows.encode(bid)
      assert BidRows.decode(row) == bid
      assert BidRows.encode(BidRows.decode(row)) == row
      assert_raise ArgumentError, fn -> BidRows.decode(Map.put(row, "new_column", 1)) end
      assert_raise ArgumentError, fn -> BidRows.decode(Map.delete(row, "priority_seq")) end
    end
  end

  test "closed and private projections keep their existing row shape and sealed amounts" do
    {:ok, bid} = offer(opened())
    state = Auction.accept_bid(opened(), bid)
    assert [%{"amounts" => []}] = Auction.public(state)

    assert [
             Map.merge(BidRows.encode(bid), %{
               "status" => "scheduled",
               "won" => false,
               "paid" => 0
             })
           ] ==
             Auction.private_bids(state, "buyer")

    closed = Auction.close_sold(%{state | clock_ms: 20}, "lot", 100, bid)
    assert [%{"amounts" => [200]}] = Auction.public(closed)
    assert [%{"paid" => 100, "won" => true}] = Auction.private_bids(closed, "buyer")
  end
end
