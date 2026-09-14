defmodule TijaraTides.Domain.MarketTransitionsTest do
  use ExUnit.Case, async: true
  alias TijaraTides.Domain.OrderBook
  alias TijaraTides.Domain.AuctionWorld, as: Auction
  alias TijaraTides.Domain.Auction, as: Lot

  defp world, do: %{entities: %{}, clock_ms: 0, revision: 1}

  defp lot do
    %Lot{
      id: "lot",
      company_id: "seller",
      warehouse_id: "storage",
      port: "Jakarta",
      good: "art",
      quantity: 10,
      reserve: 100,
      opens_ms: 10,
      closes_ms: 20,
      status: "scheduled",
      price: nil,
      winner_id: nil,
      valuation_seed: "seed"
    }
  end

  defp order do
    %OrderBook{
      id: "order",
      company_id: "buyer",
      warehouse_id: "storage",
      port: "Jakarta",
      good: "rice",
      side: "buy",
      quantity: 10,
      price: 100,
      priority_ms: 0,
      priority_seq: 1,
      expires_ms: nil
    }
  end

  test "auction registration cannot overwrite a lot or introduce a closed or invalid lot" do
    state = Auction.list(world(), lot())
    assert_raise ArgumentError, fn -> Auction.list(state, lot()) end

    for bad <- [
          %{lot() | status: "sold"},
          %{lot() | opens_ms: 0},
          %{lot() | closes_ms: 10},
          %{lot() | quantity: 0},
          %{lot() | reserve: 0}
        ] do
      assert_raise ArgumentError, fn -> Auction.list(world(), bad) end
    end
  end

  test "revision locks at opening while backing cancellation remains available" do
    state = Auction.list(world(), lot())
    revised = Auction.revise(state, "lot", 5, 200)

    assert %{quantity: 5, reserve: 200, opens_ms: 10, closes_ms: 20} =
             Auction.fetch(revised, "lot")

    opened = %{revised | clock_ms: 10}
    assert_raise ArgumentError, fn -> Auction.revise(opened, "lot", 6, 100) end
    cancelled = Auction.cancel(opened, "lot")
    assert Auction.fetch(cancelled, "lot").status == "cancelled"
    assert_raise ArgumentError, fn -> Auction.cancel(cancelled, "lot") end
    assert_raise ArgumentError, fn -> Auction.close_unsold(%{cancelled | clock_ms: 20}, "lot") end
  end

  test "settlement requires the close, reserve and winning bid, and happens only once" do
    opened = %{Auction.list(world(), lot()) | clock_ms: 10}
    {:ok, winner} = Auction.prepare_bid(opened, "lot", "buyer", "warehouse", 300, "bid")
    state = Auction.accept_bid(opened, winner)
    assert_raise ArgumentError, fn -> Auction.close_sold(state, "lot", 200, winner) end
    assert_raise ArgumentError, fn -> Auction.close_unsold(state, "lot") end
    due = %{state | clock_ms: 20}

    for price <- [99, 301, 100.5] do
      assert_raise ArgumentError, fn -> Auction.close_sold(due, "lot", price, winner) end
    end

    for bad <- [
          %{winner | auction_id: "other"},
          %{winner | company_id: "seller"},
          %{winner | id: "never-recorded"}
        ] do
      assert_raise ArgumentError, fn -> Auction.close_sold(due, "lot", 200, bad) end
    end

    {:ok, higher} = Auction.prepare_bid(state, "lot", "other-buyer", "warehouse", 400, "higher")
    outbid = %{Auction.accept_bid(state, higher) | clock_ms: 20}
    assert_raise ArgumentError, fn -> Auction.close_sold(outbid, "lot", 200, winner) end

    sold = Auction.close_sold(due, "lot", 200, winner)
    assert %{status: "sold", price: 200, winner_id: "buyer"} = Auction.fetch(sold, "lot")
    assert_raise ArgumentError, fn -> Auction.close_sold(sold, "lot", 200, winner) end
    assert_raise ArgumentError, fn -> Auction.close_unsold(sold, "lot") end
    unsold = Auction.close_unsold(due, "lot")
    assert Auction.fetch(unsold, "lot").status == "unsold"
    assert_raise ArgumentError, fn -> Auction.close_sold(unsold, "lot", 200, winner) end
  end

  test "orders reject invalid acceptance and cannot overwrite a live order" do
    state = OrderBook.accept(world(), order())
    assert_raise ArgumentError, fn -> OrderBook.accept(state, order()) end

    for bad <- [
          %{order() | side: "other"},
          %{order() | quantity: 0},
          %{order() | price: 0},
          %{order() | expires_ms: 0},
          %{order() | priority_seq: 0}
        ] do
      assert_raise ArgumentError, fn -> OrderBook.accept(world(), bad) end
    end
  end

  test "only increases and repricing reset priority, including expiry-only amendments" do
    state = %{OrderBook.accept(world(), order()) | clock_ms: 5, revision: 2}
    reduced = OrderBook.amend(state, "order", 5, 100, 20)
    assert OrderBook.priority(OrderBook.fetch(reduced, "order")) == {0, 1, "order"}
    expiry = OrderBook.amend(reduced, "order", 5, 100, 30)
    assert OrderBook.priority(OrderBook.fetch(expiry, "order")) == {0, 1, "order"}

    for {n, price} <- [{6, 100}, {5, 101}] do
      changed = OrderBook.amend(reduced, "order", n, price, nil)
      assert OrderBook.priority(OrderBook.fetch(changed, "order")) == {5, 2, "order"}
    end

    for {n, price, expiry} <- [{0, 100, nil}, {5, -1, nil}, {5, 100, 5}] do
      assert_raise ArgumentError, fn -> OrderBook.amend(state, "order", n, price, expiry) end
    end
  end

  test "fills reject stale terms even when amendments preserve quantity" do
    original = order()
    state = %{OrderBook.accept(world(), original) | clock_ms: 5, revision: 2}
    repriced = OrderBook.amend(state, original.id, original.quantity, 200, nil)
    renewed = OrderBook.amend(state, original.id, original.quantity, original.price, 20)
    repriced_back = OrderBook.amend(repriced, original.id, original.quantity, original.price, nil)

    for amended <- [repriced, renewed, repriced_back] do
      current = OrderBook.fetch(amended, original.id)
      assert current.quantity == original.quantity
      assert_raise ArgumentError, fn -> OrderBook.fill(amended, original, 3) end

      filled = OrderBook.fill(amended, current, 3)
      assert OrderBook.fetch(filled, original.id) == %{current | quantity: 7}
    end
  end

  test "partial fills retain priority and cannot overfill or apply a stale remainder" do
    state = OrderBook.accept(world(), order())

    for n <- [0, -1, 11, 1.5] do
      assert_raise ArgumentError, fn -> OrderBook.fill(state, order(), n) end
    end

    partial = OrderBook.fill(state, order(), 3)
    remainder = OrderBook.fetch(partial, "order")
    assert remainder.quantity == 7
    assert OrderBook.priority(remainder) == OrderBook.priority(order())
    assert_raise ArgumentError, fn -> OrderBook.fill(partial, order(), 3) end
    filled = OrderBook.fill(partial, remainder, 7)
    assert OrderBook.fetch(filled, "order") == nil
    assert_raise ArgumentError, fn -> OrderBook.fill(filled, remainder, 1) end
    assert_raise ArgumentError, fn -> OrderBook.amend(filled, "order", 1, 100, nil) end
    assert_raise ArgumentError, fn -> OrderBook.cancel(filled, "order") end
  end
end
