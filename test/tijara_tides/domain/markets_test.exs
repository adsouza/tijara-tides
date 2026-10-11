defmodule TijaraTides.Domain.MarketsTest do
  use ExUnit.Case, async: true
  alias TijaraTides.Domain.{Markets, State}

  test "compatibility API initializes and replenishes a depleted producer" do
    catalogue = TijaraTides.Infrastructure.GameCatalogue.all()
    state = Markets.initialize(%{clock_ms: 0, entities: %{}}, catalogue)
    market = State.get(state, "markets", "Jakarta|lumber")
    assert market["stock"] == 500
    assert market["last_production"] == 0

    state = State.put(state, "markets", "Jakarta|lumber", %{market | "stock" => 0})
    state = Markets.advance(%{state | clock_ms: 150_000}, catalogue)
    assert State.get(state, "markets", "Jakarta|lumber")["stock"] > 0
    assert State.get(state, "markets", "Jakarta|lumber")["last_production"] == 150_000
    quote = Markets.quote(state, catalogue, "Jakarta", "lumber")
    assert quote["stock"] == State.get(state, "markets", "Jakarta|lumber")["stock"]
    assert Markets.quotes(state, catalogue)["Jakarta|lumber"] == quote
  end

  test "raw cargo and handling tiers remain available through the compatibility API" do
    assert "lumber" in Markets.raw_goods()
    assert "fruit" in Markets.raw_goods()
    refute "everyday_clothing" in Markets.raw_goods()
    assert Markets.handling_rate(%{"tiers" => %{"cost" => "high"}}) == 600
    assert Markets.handling_rate(%{"tiers" => %{"cost" => "low"}}) == 200
    assert Markets.handling_rate(%{}) == 400
  end
end
