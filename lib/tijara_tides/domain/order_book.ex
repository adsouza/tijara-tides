defmodule TijaraTides.Domain.OrderBook do
  @moduledoc "Standing standardized-cargo orders, price-time priority and bounded public trade history."

  @fields ~w(id company_id warehouse_id port good side quantity price priority_ms priority_seq expires_ms)a
  @enforce_keys @fields
  defstruct @fields

  def supported?(item),
    do:
      is_map(item) and item["category"] in ["Bulk commodities", "Mass consumer products", "Scrap"]

  @doc "Accept a new order without overwriting an existing order's priority or terms."
  def accept(%__MODULE__{} = order, clock_ms, revision, id_taken?) do
    unless not id_taken? and order.side in ["buy", "sell"] and
             order.priority_ms == clock_ms and order.priority_seq == revision,
           do: raise(ArgumentError, "A new order requires a unique ID, side and current priority")

    terms!(order.quantity, order.price, order.expires_ms, clock_ms)
    order
  end

  def amend(%__MODULE__{} = o, quantity, price, expires_ms, clock_ms, revision) do
    terms!(quantity, price, expires_ms, clock_ms)
    reset = quantity > o.quantity or price != o.price

    %{
      o
      | quantity: quantity,
        price: price,
        expires_ms: expires_ms,
        priority_ms: if(reset, do: clock_ms, else: o.priority_ms),
        priority_seq: if(reset, do: revision, else: o.priority_seq)
    }
  end

  def fill(%__MODULE__{} = current, %__MODULE__{} = o, n) do
    unless current == o and is_integer(n) and n > 0 and n <= current.quantity,
      do:
        raise(
          ArgumentError,
          "A fill requires a current order and a positive quantity within its remainder"
        )

    if n == current.quantity,
      do: :filled,
      else: %{current | quantity: current.quantity - n}
  end

  defp terms!(quantity, price, expiry, clock) do
    unless is_integer(quantity) and quantity in 1..TijaraTides.Domain.CargoRules.max_lots() and
             is_integer(price) and price in 1..1_000_000_000_000 and
             (is_nil(expiry) or
                (is_integer(expiry) and expiry > clock and expiry <= 9_000_000_000_000_000)),
           do:
             raise(
               ArgumentError,
               "Order terms require a bounded quantity, price and future expiry"
             )
  end

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

  def counterparts(candidates, %__MODULE__{} = incoming) do
    candidates
    |> Enum.filter(
      &(&1.port == incoming.port and &1.good == incoming.good and &1.side != incoming.side and
          &1.company_id != incoming.company_id)
    )
    |> Enum.filter(
      &if incoming.side == "buy", do: &1.price <= incoming.price, else: &1.price >= incoming.price
    )
    |> Enum.sort_by(&{if(incoming.side == "buy", do: &1.price, else: -&1.price), priority(&1)})
  end
end
