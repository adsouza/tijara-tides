defmodule TijaraTides.Domain.PortCargoMarketWorld do
  @moduledoc "Loads typed markets and records their transitions within the atomic world."
  import TijaraTides.Domain.State, only: [get: 3, entities: 2, put: 4]
  alias TijaraTides.Domain.PortCargoMarket, as: Market
  alias TijaraTides.Domain.PortCargoMarket.{Lots, Rows}
  alias TijaraTides.Domain.Ship.CargoBatch

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

    {state |> record_lots(lots) |> store(market), Enum.map(cargo, &CargoBatch.to_row/1)}
  end

  def accept_cargo(state, port, good, quantity, price),
    do: store(state, Market.receive_cargo(fetch(state, port, good), quantity, price))

  def auction_supply(state, port, good, quantity, amount, item) do
    {lots, market, cargo} =
      Market.auction_supply(lots(state), fetch(state, port, good), quantity, amount, item)

    {state |> record_lots(lots) |> store(market), Enum.map(cargo, &CargoBatch.to_row/1)}
  end

  def auction_consume(state, port, good, quantity, amount),
    do: store(state, Market.auction_consume(fetch(state, port, good), quantity, amount))

  def quote(state, catalogue, port, good) do
    market = fetch(state, port, good)

    if market && catalogue["goods"][good] do
      Market.quote(market, catalogue)
      |> Map.update!("freshness_batches", &Enum.map(&1, fn batch -> Rows.encode_batch(batch) end))
    end
  end

  def initialize(state, catalogue) do
    Market.validate_catalogue!(catalogue)

    if map_size(entities(state, "markets")) == 0 do
      Enum.reduce(catalogue["ports"], state, fn {port, definition}, state ->
        Enum.reduce(definition["roles"], state, fn {good, role}, state ->
          {lots, market} =
            Market.initialize(lots(state), port, good, role, catalogue["goods"][good])

          state |> record_lots(lots) |> store(market)
        end)
      end)
    else
      state
    end
  end

  def advance(state, catalogue) do
    Enum.reduce(entities(state, "markets"), state, fn {_, row}, state ->
      market = Rows.decode(row)
      {lots, market} = Market.replenish(lots(state), market, catalogue["goods"][market.good])
      state |> record_lots(lots) |> store(market)
    end)
  end
end
