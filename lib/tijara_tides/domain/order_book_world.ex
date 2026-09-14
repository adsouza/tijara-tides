defmodule TijaraTides.Domain.OrderBookWorld do
  @moduledoc "Standing standardized-cargo orders, price-time priority and bounded public trade history."
  import TijaraTides.Domain.State

  alias TijaraTides.Domain.OrderBook
  alias TijaraTides.Domain.OrderBook.Rows

  def orders(state), do: Enum.map(Map.values(entities(state, "exchange_orders")), &Rows.decode/1)

  def fetch(state, id) do
    case get(state, "exchange_orders", id) do
      nil -> nil
      row -> Rows.decode(row)
    end
  end

  def accept(state, %OrderBook{} = order) do
    store(
      state,
      OrderBook.accept(order, state.clock_ms, state.revision, fetch(state, order.id) != nil)
    )
  end

  def amend(state, id, quantity, price, expires_ms) do
    store(
      state,
      OrderBook.amend(
        fetch!(state, id),
        quantity,
        price,
        expires_ms,
        state.clock_ms,
        state.revision
      )
    )
  end

  def cancel(state, id) do
    fetch!(state, id)
    delete(state, "exchange_orders", id)
  end

  def fill(state, %OrderBook{} = order, quantity) do
    case OrderBook.fill(fetch!(state, order.id), order, quantity) do
      :filled -> cancel(state, order.id)
      remainder -> store(state, remainder)
    end
  end

  def company_orders(state, id),
    do: Enum.map(owned(state, "exchange_orders", "company_id", id), &Rows.decode/1)

  defp fetch!(state, id) do
    fetch(state, id) || raise ArgumentError, "Order does not exist"
  end

  defp store(state, order), do: put(state, "exchange_orders", order.id, Rows.encode(order))

  def counterparts(state, incoming) do
    owned(state, "exchange_orders", "book_key", incoming.port <> "|" <> incoming.good)
    |> Enum.map(&Rows.decode/1)
    |> OrderBook.counterparts(incoming)
  end

  def record_trade(state, port, good, n, price, id) do
    row = %{
      "id" => id,
      "port" => port,
      "good" => good,
      "quantity" => n,
      "price" => price,
      "clock_ms" => state.clock_ms,
      "sequence" => state.revision
    }

    state = put(state, "exchange_trades", id, row)

    owned(state, "exchange_trades", "book_key", port <> "|" <> good)
    |> Enum.sort_by(&{&1["clock_ms"], &1["sequence"], &1["id"]}, :desc)
    |> Enum.drop(20)
    |> Enum.reduce(state, &delete(&2, "exchange_trades", &1["id"]))
  end

  def public(state) do
    orders(state)
    |> Enum.group_by(&(&1.port <> "|" <> &1.good))
    |> Map.new(fn {key, os} ->
      levels =
        os
        |> Enum.group_by(&{&1.side, &1.price})
        |> Enum.map(fn {{side, price}, rows} ->
          %{
            "side" => side,
            "price" => price,
            "quantity" => Enum.sum(Enum.map(rows, & &1.quantity))
          }
        end)

      {key, Enum.sort_by(levels, &{&1["side"], &1["price"]})}
    end)
  end

  def recent(state),
    do:
      entities(state, "exchange_trades")
      |> Map.values()
      |> Enum.sort_by(&{&1["clock_ms"], &1["sequence"], &1["id"]}, :desc)
      |> Enum.map(&Map.drop(&1, ["id"]))
      |> Enum.group_by(&(&1["port"] <> "|" <> &1["good"]))
end
