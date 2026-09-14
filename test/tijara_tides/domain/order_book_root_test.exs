defmodule TijaraTides.Domain.OrderBookRootTest do
  use ExUnit.Case, async: true
  alias TijaraTides.Domain.OrderBook
  alias TijaraTides.Domain.OrderBook.Rows

  defp order do
    %OrderBook{
      id: "o",
      company_id: "c",
      warehouse_id: "w",
      port: "p",
      good: "grain",
      side: "buy",
      quantity: 10,
      price: 100,
      priority_ms: 0,
      priority_seq: 1,
      expires_ms: nil
    }
  end

  test "pure transitions preserve priority, reject stale fills and explicitly exhaust orders" do
    original = OrderBook.accept(order(), 0, 1, false)
    reduced = OrderBook.amend(original, 5, 100, nil, 10, 2)
    assert OrderBook.priority(reduced) == {0, 1, "o"}
    repriced = OrderBook.amend(reduced, 5, 200, nil, 10, 2)
    assert OrderBook.priority(repriced) == {10, 2, "o"}
    assert_raise ArgumentError, fn -> OrderBook.fill(repriced, reduced, 1) end
    assert OrderBook.fill(repriced, repriced, 5) == :filled
    assert Rows.decode(Rows.encode(original)) == original
  end

  test "counterparts filter self trades and rank price before time" do
    incoming = order()
    seller = %{incoming | id: "s", company_id: "seller", side: "sell"}
    cheap = %{seller | id: "cheap", price: 90, priority_seq: 2}

    assert OrderBook.counterparts([%{seller | company_id: "c"}, seller, cheap], incoming) == [
             cheap,
             seller
           ]
  end
end
