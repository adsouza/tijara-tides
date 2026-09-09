defmodule TijaraTides.Domain.Markets do
  @moduledoc "Finite market quotes, catalogue rules, producer output, demand and buyer-budget recovery."
  import TijaraTides.Domain.State, only: [get: 3, entities: 2, put: 4]
  alias TijaraTides.Domain.CargoLots
  @market_replenishment_ms 150_000

  def quote(state, catalogue, port, good) do
    market = get(state, "markets", port <> "|" <> good)
    item = catalogue["goods"][good]

    if market && item do
      clustered = Enum.any?(catalogue["clusters"], fn {_, ports} -> port in ports end)
      ask_base = if market["merchant"] or clustered, do: 105, else: 90
      bid_base = if market["merchant"] or clustered, do: 95, else: 110

      %{
        "ask" => div(item["reference_cents"] * (ask_base + div(500 - market["stock"], 25)), 100),
        "bid" => div(item["reference_cents"] * (bid_base - div(500 - market["demand"], 25)), 100),
        "handling_fee" => handling_rate(catalogue["ports"][port]),
        "freshness_batches" => market["batches"],
        "stock" => market["stock"],
        "demand" => market["demand"],
        "buyer_budget" => market["budget"],
        "manual" => item["manual"] and not market["merchant"]
      }
    end
  end

  defp validate_catalogue!(catalogue) do
    Enum.each(catalogue["goods"], fn {id, item} ->
      unless Regex.match?(~r/^[a-z]+(_[a-z]+)*$/, id) and item["id"] == id and
               is_binary(item["name"]) and String.trim(item["name"]) != "",
             do: raise(ArgumentError, "cargo requires a machine ID and display name: #{id}")
    end)

    Enum.each(raw_goods(), fn good ->
      unless Map.has_key?(catalogue["goods"], good),
        do: raise(ArgumentError, "unknown raw production good: #{good}")
    end)

    Enum.each(catalogue["ports"], fn {port, definition} ->
      Enum.each(definition["roles"], fn {good, role} ->
        unless Map.has_key?(catalogue["goods"], good),
          do: raise(ArgumentError, "unknown role good at #{port}: #{good}")

        if catalogue["goods"][good]["shelf_ms"] > 0 and String.contains?(role, "/"),
          do: raise(ArgumentError, "perishable merchant markets are not supported")
      end)
    end)
  end

  def raw_goods,
    do: [
      "iron_ore",
      "grain",
      "lumber",
      "crude_oil",
      "fruit",
      "seafood",
      "meat",
      "aluminium_scrap",
      "copper_scrap",
      "recovered_plastics"
    ]

  def handling_rate(%{"tiers" => %{"cost" => "high"}}), do: 600
  def handling_rate(%{"tiers" => %{"cost" => "low"}}), do: 200
  def handling_rate(_), do: 400

  def initialize(state, catalogue) do
    validate_catalogue!(catalogue)

    if map_size(entities(state, "markets")) == 0 do
      Enum.reduce(catalogue["ports"], state, fn {port, definition}, state ->
        Enum.reduce(definition["roles"], state, fn {good, role}, state ->
          merchant = String.contains?(role, "/")
          seller = String.contains?(role, "exp")
          buyer = String.contains?(role, "imp")

          item = catalogue["goods"][good]

          {state, batches} =
            if item["shelf_ms"] > 0 and seller and not merchant do
              {next, lot} = CargoLots.create(state, good, 500, state.clock_ms + item["shelf_ms"])
              {next, [lot]}
            else
              {state, []}
            end

          market = %{
            "port" => port,
            "good" => good,
            "merchant" => merchant,
            "seller" => seller,
            "buyer" => buyer,
            "stock" => if(seller and not merchant, do: 500, else: 0),
            "demand" => if(buyer, do: 500, else: 0),
            "budget" => item["reference_cents"] * 1000,
            "batches" => batches,
            "last_production" => state.clock_ms
          }

          put(state, "markets", port <> "|" <> good, market)
        end)
      end)
    else
      state
    end
  end

  def advance(state, catalogue) do
    now = state.clock_ms

    Enum.reduce(entities(state, "markets"), state, fn {id, market}, state ->
      replenished = div(now - market["last_production"], @market_replenishment_ms)
      item = catalogue["goods"][market["good"]]
      batches = Enum.reject(market["batches"], &(&1["expires_ms"] <= now))

      stock =
        if item["shelf_ms"] > 0,
          do: Enum.sum(Enum.map(batches, & &1["quantity"])),
          else: market["stock"]

      market = %{market | "batches" => batches, "stock" => stock}
      state = put(state, "markets", id, market)

      if replenished > 0 do
        # Manufactured supply is a finite initial allocation until input purchasing
        # and recipes are implemented. Never synthesize re-export merchant stock.
        raw = market["good"] in raw_goods()

        produced =
          if raw and market["seller"] and not market["merchant"],
            do: min(max(0, 500 - stock), replenished),
            else: 0

        {state, batches} =
          if item["shelf_ms"] > 0 and produced > 0 do
            {next, lot} =
              CargoLots.create(state, market["good"], produced, now + item["shelf_ms"])

            {next, batches ++ [lot]}
          else
            {state, batches}
          end

        market = %{
          market
          | "stock" => stock + produced,
            "batches" => batches,
            "budget" =>
              min(
                item["reference_cents"] * 1000,
                market["budget"] +
                  if(market["buyer"], do: replenished * item["reference_cents"], else: 0)
              ),
            "demand" =>
              min(500, market["demand"] + if(market["buyer"], do: replenished, else: 0)),
            "last_production" =>
              market["last_production"] + replenished * @market_replenishment_ms
        }

        put(state, "markets", id, market)
      else
        state
      end
    end)
  end
end
