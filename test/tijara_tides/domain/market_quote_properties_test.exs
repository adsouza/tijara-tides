defmodule TijaraTides.Domain.MarketQuotePropertiesTest do
  use ExUnit.Case, async: true
  use ExUnitProperties
  alias TijaraTides.Domain.PortCargoMarket, as: Market
  alias TijaraTides.Domain.PortCargoMarket.Rows

  # Hand-authored points in the ordinary scarcity/spread schedule. Vary scale and
  # demand independently; comparing two calls to quote would share its defect.
  @stock [0, 250, 500]
  @asks %{false => [110, 100, 90], true => [125, 115, 105]}
  @bids %{false => [90, 100, 110], true => [75, 85, 95]}

  property "scarcity price points scale in cents and merchant spread stays distinct" do
    check all(
            reference <- integer(1..1_000_000),
            stock <- integer(0..2),
            demand <- integer(0..2),
            merchant <- boolean(),
            manual <- boolean(),
            max_runs: 50,
            max_shrinking_steps: 100
          ) do
      market = market(merchant, Enum.at(@stock, stock), Enum.at(@stock, demand))
      quote = Market.quote(market, catalogue(reference, manual))
      assert quote["ask"] == div(reference * Enum.at(@asks[merchant], stock), 100)
      assert quote["bid"] == div(reference * Enum.at(@bids[merchant], demand), 100)
      assert quote["manual"] == (manual and not merchant)

      assert Market.quote(%{market | warehouse_active: true}, catalogue(reference, manual))[
               "manual"
             ] == manual
    end
  end

  property "buyer capacity uses independently generated paid units and protects zero-price demand" do
    check all(
            paid_units <- integer(0..100),
            remainder <- integer(0..19),
            demand <- integer(0..100),
            zero_price <- boolean(),
            max_runs: 50,
            max_shrinking_steps: 100
          ) do
      bid = if zero_price, do: 0, else: 20
      quote = %{"bid" => bid, "demand" => demand, "buyer_budget" => paid_units * 20 + remainder}
      expected = if zero_price, do: demand, else: min(demand, paid_units)
      assert Market.sale_capacity(quote) == expected
    end
  end

  test "buyer budget below one priced unit cannot purchase demand" do
    for {budget, expected} <- [{0, 0}, {19, 0}, {20, 1}, {39, 1}, {200, 10}] do
      assert Market.sale_capacity(%{"bid" => 20, "demand" => 10, "buyer_budget" => budget}) ==
               expected
    end

    assert Market.sale_capacity(%{"bid" => 0, "demand" => 10, "buyer_budget" => 0}) == 10
  end

  test "ordinary scarcity endpoints remain explicit fixed counterexamples" do
    for {stock, ask} <- [{0, 110}, {250, 100}, {500, 90}] do
      assert Market.quote(market(false, stock, 500), catalogue(100))["ask"] == ask
    end
  end

  test "new and decoded merchants need explicitly active warehouse backing" do
    m = market(true, 10, 10)
    refute m.warehouse_active
    refute Market.quote(m, catalogue(100))["manual"]
    restored = m |> Rows.encode() |> Rows.decode()
    refute restored.warehouse_active
    refute Market.quote(restored, catalogue(100))["manual"]
    assert Market.quote(%{restored | warehouse_active: true}, catalogue(100))["manual"]
  end

  defp market(merchant, stock, demand) do
    %Market{
      port: "Jakarta",
      good: "lumber",
      merchant: merchant,
      seller: true,
      buyer: true,
      stock: stock,
      demand: demand,
      budget: 1_000_000,
      batches: [],
      last_production: 0
    }
  end

  defp catalogue(reference, manual \\ true),
    do: %{
      "goods" => %{
        "lumber" => %{
          "id" => "lumber",
          "reference_cents" => reference,
          "manual" => manual,
          "shelf_ms" => 0
        }
      },
      "ports" => %{}
    }
end
