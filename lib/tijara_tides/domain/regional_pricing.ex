defmodule TijaraTides.Domain.RegionalPricing do
  @moduledoc "Inventory-driven regional NPC prices; physical markets and player orders remain local."
  alias TijaraTides.Domain.PortCargoMarket

  # Source-configured launch tuning. No observed trade prices enter this calculation.
  @lower_bps 8000
  @upper_bps 12000
  @response_bps 2000
  @local_bps 200
  @spread_bps 100
  # Stock and demand each run 0..500, so that span saturates a response.
  @imbalance_scale 500

  def prices(markets, catalogue) do
    item = catalogue["goods"][hd(markets).good]
    reference = item["reference_cents"]
    # Ordinary merchant trading is deferred, but luxury merchants already buy
    # player consignments and relist acquired stock through scheduled auctions.
    active = Enum.filter(markets, &(not &1.merchant or item["category"] == "Luxury items"))
    sellers = Enum.filter(active, & &1.seller)
    buyers = Enum.filter(active, & &1.buyer)
    supply = average(sellers, :stock)
    demand = average(buyers, :demand)
    pressure = div((demand - supply) * @response_bps, @imbalance_scale)
    center = clamp(10_000 + pressure, @lower_bps, @upper_bps)

    quotes =
      Map.new(markets, fn market ->
        local =
          clamp(
            div(
              (market.demand - market.stock - (demand - supply)) * @local_bps,
              @imbalance_scale
            ),
            -@local_bps,
            @local_bps
          )

        ask = div(reference * clamp(center + local + @spread_bps, @lower_bps, @upper_bps), 10_000)
        bid = div(reference * clamp(center + local - @spread_bps, @lower_bps, @upper_bps), 10_000)
        {market.port, %{ask: max(1, ask), bid: max(1, bid)}}
      end)

    # Bound every executable bid against every stocked source, including differing
    # port handling fees. Zero allowance for fuel/upkeep is intentionally conservative.
    # Recompute on each quote, so fills and replenishment cannot leave stale bounds.
    Map.new(markets, fn market ->
      quote = quotes[market.port]

      bid =
        Enum.reduce(sellers, quote.bid, fn seller, bid ->
          if seller.stock > 0 do
            allowance =
              PortCargoMarket.handling_rate(catalogue["ports"][seller.port]) +
                PortCargoMarket.handling_rate(catalogue["ports"][market.port])

            min(bid, quotes[seller.port].ask + allowance)
          else
            bid
          end
        end)

      {market.port, %{quote | bid: bid}}
    end)
  end

  defp average([], _field), do: 0

  defp average(markets, field),
    do: div(Enum.sum(Enum.map(markets, &Map.fetch!(&1, field))), length(markets))

  defp clamp(value, low, high), do: min(high, max(low, value))
end
