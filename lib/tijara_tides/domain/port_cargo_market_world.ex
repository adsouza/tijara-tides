defmodule TijaraTides.Domain.PortCargoMarketWorld do
  alias TijaraTides.Domain.Ship.CargoRows
  @moduledoc "Loads typed markets and records their transitions within the atomic world."
  import TijaraTides.Domain.State, only: [get: 3, entities: 2, put: 4]
  alias TijaraTides.Domain.PortCargoMarket, as: Market
  alias TijaraTides.Domain.PortCargoMarket.{Lots, Rows}
  alias TijaraTides.Domain.Manufacturing
  alias TijaraTides.Domain.RegionalPricing

  def fetch(state, port, good) do
    case get(state, "markets", port <> "|" <> good) do
      nil -> nil
      row -> Rows.decode(row)
    end
  end

  defp store(state, %Market{} = market),
    do: put(state, "markets", market.port <> "|" <> market.good, Rows.encode(market))

  defp lots(state),
    do: %Lots{
      clock_ms: state.clock_ms,
      lot_allocation: Map.get(state, :lot_allocation, {:local, 1})
    }

  defp record_lots(state, %Lots{} = lots) do
    # A no-allocation transition must not introduce transient allocation fields.
    if lots.new_lots == [] do
      state
    else
      state
      |> Map.put(:lot_allocation, lots.lot_allocation)
      |> Map.update(:new_lots, lots.new_lots, &(&1 ++ lots.new_lots))
    end
  end

  def release_stock(state, port, good, quantity, price, item) do
    {lots, market, cargo} =
      Market.supply(lots(state), fetch(state, port, good), quantity, price, item)

    {state |> record_lots(lots) |> store(market), Enum.map(cargo, &CargoRows.encode/1)}
  end

  def accept_cargo(state, port, good, quantity, price),
    do: store(state, Market.receive_cargo(fetch(state, port, good), quantity, price))

  def auction_supply(state, port, good, quantity, amount, item) do
    {lots, market, cargo} =
      Market.auction_supply(lots(state), fetch(state, port, good), quantity, amount, item)

    {state |> record_lots(lots) |> store(market), Enum.map(cargo, &CargoRows.encode/1)}
  end

  def auction_consume(state, port, good, quantity, amount),
    do: store(state, Market.auction_consume(fetch(state, port, good), quantity, amount))

  def quote(state, catalogue, port, good) do
    market = fetch(state, port, good)

    if market && catalogue["goods"][good] do
      ports = cluster(catalogue, port)
      prices = ports && RegionalPricing.prices(cluster_markets(state, ports, good), catalogue)
      build_quote(market, catalogue, prices && prices[port])
    end
  end

  @doc "Every quote for one revision, pricing each cluster once per good rather than once per member port."
  def quotes(state, catalogue) do
    regional =
      for {_, ports} <- catalogue["clusters"] || %{},
          good <- Map.keys(catalogue["goods"]),
          markets = cluster_markets(state, ports, good),
          markets != [],
          {port, prices} <- RegionalPricing.prices(markets, catalogue),
          into: %{},
          do: {port <> "|" <> good, prices}

    Map.new(entities(state, "markets"), fn {id, row} ->
      {id, build_quote(Rows.decode(row), catalogue, regional[id])}
    end)
  end

  defp cluster(catalogue, port),
    do:
      Enum.find_value(catalogue["clusters"] || %{}, fn {_, ports} ->
        if port in ports, do: ports
      end)

  defp cluster_markets(state, ports, good),
    do: ports |> Enum.map(&fetch(state, &1, good)) |> Enum.reject(&is_nil/1)

  defp build_quote(market, catalogue, prices) do
    Market.quote(market, catalogue)
    |> Map.merge(if(prices, do: %{"ask" => prices.ask, "bid" => prices.bid}, else: %{}))
    |> Map.update!("freshness_batches", &Enum.map(&1, fn batch -> Rows.encode_batch(batch) end))
  end

  def initialize(state, catalogue) do
    Market.validate_catalogue!(catalogue)

    if map_size(entities(state, "markets")) == 0 do
      Enum.reduce(catalogue["ports"], state, fn {port, definition}, state ->
        Enum.reduce(definition["roles"], state, fn {good, role}, state ->
          {lots, market} =
            Market.initialize(lots(state), port, good, role, catalogue["goods"][good])

          feedstock =
            MapSet.member?(Manufacturing.inputs_at(catalogue, port), good) and not market.merchant

          market =
            if feedstock,
              do: %{
                market
                | feedstock: true,
                  buyer: true,
                  stock: max(market.stock, 50),
                  demand: min(market.demand + 450, 500 - max(market.stock, 50))
              },
              else: market

          state |> record_lots(lots) |> store(market)
        end)
      end)
    else
      Enum.reduce(entities(state, "markets"), state, fn {_, row}, s ->
        market = Rows.decode(row)

        feedstock =
          MapSet.member?(Manufacturing.inputs_at(catalogue, market.port), market.good) and
            not market.merchant

        if feedstock and not market.feedstock,
          do:
            store(s, %{
              market
              | feedstock: true,
                buyer: true,
                demand: min(500 - market.stock, max(50, market.demand))
            }),
          else: s
      end)
    end
  end

  def advance(state, catalogue) do
    scale = Map.get(state, :participation_bps, 10_000)
    quarters = TijaraTides.Domain.Participation.settings(catalogue)["budget_quarters"]

    cycles =
      Map.new(entities(state, "markets"), fn {id, row} ->
        {id,
         elem(
           TijaraTides.Domain.Participation.cycles(
             div(state.clock_ms - row["last_production"], 150_000),
             scale,
             row["production_credit"] || 0
           ),
           0
         )}
      end)

    state =
      Enum.reduce(entities(state, "markets"), state, fn {_, row}, state ->
        market = Rows.decode(row)

        {lots, market} =
          Market.replenish(lots(state), market, catalogue["goods"][market.good], scale, quarters)

        state |> record_lots(lots) |> store(market)
      end)

    Enum.reduce(Enum.sort(entities(state, "markets")), state, fn {id, row}, s ->
      recipe = Manufacturing.recipes(catalogue)[row["good"]]

      if recipe != nil and row["seller"] and not row["merchant"] and cycles[id] > 0 do
        inputs =
          Map.new(recipe["inputs"], fn {good, _} -> {good, fetch(s, row["port"], good)} end)

        if Enum.all?(inputs, fn {_, market} -> market != nil and market.feedstock end) do
          prices =
            Map.new(inputs, fn {good, _} ->
              {good, quote(s, catalogue, row["port"], good)["ask"]}
            end)

          {output, consumed} =
            Manufacturing.produce(
              fetch(s, row["port"], row["good"]),
              inputs,
              recipe,
              prices,
              cycles[id]
            )

          Enum.reduce(consumed, store(s, output), fn {_, input}, s -> store(s, input) end)
        else
          s
        end
      else
        s
      end
    end)
  end
end
