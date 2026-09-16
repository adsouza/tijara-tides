defmodule TijaraTides.Domain.RegionalPricingTest do
  use ExUnit.Case, async: true
  alias TijaraTides.Domain.{PortCargoMarket, PortCargoMarketWorld, RegionalPricing}
  alias PortCargoMarket.Rows

  defp market(port, stock, demand, merchant \\ false),
    do: %PortCargoMarket{
      port: port,
      good: "lumber",
      merchant: merchant,
      seller: true,
      buyer: true,
      stock: stock,
      demand: demand,
      budget: 100_000_000,
      batches: [],
      last_production: 0
    }

  defp catalogue,
    do: %{
      "clusters" => %{"region" => ["a", "b", "c"]},
      "ports" => %{
        "a" => %{"tiers" => %{"cost" => "low"}},
        "b" => %{"tiers" => %{"cost" => "high"}},
        "c" => %{"tiers" => %{"cost" => "low"}}
      },
      "goods" => %{"lumber" => %{"reference_cents" => 100_000, "manual" => true}}
    }

  test "all executable pairs stay within handling costs under asymmetric depletion" do
    cat = catalogue()

    for stock_a <- [0, 1, 50, 250, 500],
        stock_b <- [0, 1, 500],
        demand_a <- [0, 1, 500],
        demand_b <- [0, 500],
        stock_c <- [0, 500],
        demand_c <- [0, 500] do
      markets = [
        market("a", stock_a, demand_a),
        market("b", stock_b, demand_b),
        market("c", stock_c, demand_c)
      ]

      prices = RegionalPricing.prices(markets, cat)

      for seller <- markets, buyer <- markets, seller.stock > 0, buyer.demand > 0 do
        allowance =
          PortCargoMarket.handling_rate(cat["ports"][seller.port]) +
            PortCargoMarket.handling_rate(cat["ports"][buyer.port])

        assert prices[buyer.port].bid - prices[seller.port].ask <= allowance
      end

      for {_, quote} <- prices do
        assert quote.ask in 80_000..120_000
        assert quote.bid in 80_000..120_000
      end
    end
  end

  test "an inactive standardized-cargo merchant moves neither regional aggregate" do
    cat = catalogue()
    plain = RegionalPricing.prices([market("a", 500, 0), market("b", 0, 500)], cat)

    with_merchant =
      RegionalPricing.prices(
        [market("a", 500, 0), market("b", 0, 500), market("c", 500, 500, true)],
        cat
      )

    assert with_merchant["a"] == plain["a"]
    assert with_merchant["b"] == plain["b"]
  end

  test "luxury merchant demand and acquired stock both affect neighboring quotes" do
    cat = put_in(catalogue(), ["goods", "lumber", "category"], "Luxury items")
    supplier = %{market("a", 250, 0) | buyer: false}
    merchant = market("b", 0, 500, true)
    prices = RegionalPricing.prices([supplier, merchant], cat)
    demand_used = RegionalPricing.prices([supplier, %{merchant | demand: 0}], cat)
    stocked = RegionalPricing.prices([supplier, %{merchant | stock: 500}], cat)
    assert demand_used["a"].ask < prices["a"].ask
    assert stocked["a"].ask < prices["a"].ask
  end

  test "Hong Kong luxury auction consumption reprices its catchment in individual and batch queries" do
    cat = TijaraTides.Infrastructure.GameCatalogue.all()
    state = PortCargoMarketWorld.initialize(%{entities: %{}, clock_ms: 0}, cat)
    before = PortCargoMarketWorld.quote(state, cat, "Shenzhen", "whisky")
    next = PortCargoMarketWorld.auction_consume(state, "Hong Kong", "whisky", 500, 100_000)
    after_quote = PortCargoMarketWorld.quote(next, cat, "Shenzhen", "whisky")
    assert after_quote["ask"] < before["ask"]
    assert after_quote["bid"] < before["bid"]
    assert PortCargoMarketWorld.quotes(next, cat)["Shenzhen|whisky"] == after_quote

    assert next.entities["markets"]["Shenzhen|whisky"] ==
             state.entities["markets"]["Shenzhen|whisky"]

    assert next.entities["markets"]["Hong Kong|whisky"]["stock"] == 500
    assert next.entities["markets"]["Hong Kong|whisky"]["demand"] == 0
  end

  test "a neighbor's stock changes the shared quote without moving local inventory" do
    cat = catalogue()
    a = market("a", 500, 500)
    b = market("b", 500, 500)

    state = %{
      clock_ms: 0,
      entities: %{"markets" => %{"a|lumber" => Rows.encode(a), "b|lumber" => Rows.encode(b)}}
    }

    quote = PortCargoMarketWorld.quote(state, cat, "a", "lumber")
    depleted = put_in(state, [:entities, "markets", "b|lumber", "stock"], 1)
    changed = PortCargoMarketWorld.quote(depleted, cat, "a", "lumber")
    assert changed["ask"] > quote["ask"]
    assert changed["stock"] == quote["stock"]
    assert changed["demand"] == quote["demand"]
    assert changed["buyer_budget"] == quote["buyer_budget"]
    assert PortCargoMarketWorld.quote(state, cat, "a", "lumber") == quote
  end
end
