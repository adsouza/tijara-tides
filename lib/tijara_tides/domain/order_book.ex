defmodule TijaraTides.Domain.OrderBook do
  @moduledoc "Standing standardized-cargo orders, price-time priority and bounded public trade history."
  import TijaraTides.Domain.State

  @fields ~w(id company_id warehouse_id port good side quantity price priority_ms priority_seq expires_ms)a
  @enforce_keys @fields
  defstruct @fields

  def supported?(item),
    do:
      is_map(item) and item["category"] in ["Bulk commodities", "Mass consumer products", "Scrap"]

  def from_row(row),
    do: struct!(__MODULE__, Map.new(@fields, &{&1, Map.fetch!(row, Atom.to_string(&1))}))

  def to_row(o), do: Map.new(@fields, &{Atom.to_string(&1), Map.fetch!(o, &1)})
  def orders(state), do: Enum.map(Map.values(entities(state, "exchange_orders")), &from_row/1)

  def fetch(state, id) do
    case get(state, "exchange_orders", id) do
      nil -> nil
      row -> from_row(row)
    end
  end

  def accept(state, %__MODULE__{} = order),
    do: put(state, "exchange_orders", order.id, to_row(order))

  def remove(state, id), do: delete(state, "exchange_orders", id)

  def fill(state, o, n),
    do:
      if(n == o.quantity,
        do: remove(state, o.id),
        else: accept(state, %{o | quantity: o.quantity - n})
      )

  def priority(o), do: {o.priority_ms, o.priority_seq, o.id}

  def claim(%__MODULE__{} = o),
    do:
      TijaraTides.Domain.Warehouse.Claim.new(
        id: o.id,
        kind: :order,
        company_id: o.company_id,
        warehouse_id: o.warehouse_id,
        good: o.good,
        quantity: o.quantity,
        side: o.side
      )

  def counterparts(state, incoming) do
    owned(state, "exchange_orders", "book_key", incoming.port <> "|" <> incoming.good)
    |> Enum.map(&from_row/1)
    |> Enum.filter(
      &(&1.port == incoming.port and &1.good == incoming.good and &1.side != incoming.side and
          &1.company_id != incoming.company_id)
    )
    |> Enum.filter(
      &if incoming.side == "buy", do: &1.price <= incoming.price, else: &1.price >= incoming.price
    )
    |> Enum.sort_by(&{if(incoming.side == "buy", do: &1.price, else: -&1.price), priority(&1)})
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
