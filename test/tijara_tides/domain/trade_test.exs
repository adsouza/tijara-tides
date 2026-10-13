defmodule TijaraTides.Domain.TradeTest do
  use ExUnit.Case, async: true
  alias TijaraTides.Domain.{Prices, Trade}

  test "a buy margin raises the ceiling, rounding up to the next cent" do
    assert Trade.queued_limit("buy", 10_000, 0) == 10_000
    assert Trade.queued_limit("buy", 10_000, 50) == 10_050
    assert Trade.queued_limit("buy", 10_000, 200) == 10_200
    assert Trade.queued_limit("buy", 10_000, 1_000) == 11_000
    # 101 * 1.02 = 103.02
    assert Trade.queued_limit("buy", 101, 200) == 104
    assert Trade.queued_limit("buy", 0, 1_000) == 0
  end

  test "a sell margin lowers the floor, rounding down to the cent" do
    assert Trade.queued_limit("sell", 10_000, 0) == 10_000
    assert Trade.queued_limit("sell", 10_000, 50) == 9_950
    assert Trade.queued_limit("sell", 10_000, 200) == 9_800
    assert Trade.queued_limit("sell", 10_000, 1_000) == 9_000
    # 101 * 0.98 = 98.98
    assert Trade.queued_limit("sell", 101, 200) == 98
    assert Trade.queued_limit("sell", 0, 1_000) == 0
  end

  test "a widened buy limit never passes the player price ceiling" do
    assert Prices.max_cents() == 1_000_000_000_000
    assert Trade.queued_limit("buy", 1_000_000_000_000, 1_000) == 1_000_000_000_000
    assert Trade.queued_limit("buy", 999_999_999_999, 1) == 1_000_000_000_000
    assert Trade.queued_limit("buy", 950_000_000_000, 500) == 997_500_000_000
  end

  test "margins are bounded at ten percent" do
    assert Trade.max_margin_bps() == 1_000
    assert %Trade{side: "buy", ship_id: "s", good: "g", quantity: 1, limit: 1}.margin_bps == nil
    refute %Trade{side: "buy", ship_id: "s", good: "g", quantity: 1, limit: 1}.save_margin
  end
end
