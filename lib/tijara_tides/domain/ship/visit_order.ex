defmodule TijaraTides.Domain.Ship.VisitOrder do
  @moduledoc "Snapshot of a visit's committed instruction terms and monotonic settlement progress."
  @fields ~w(id ship_id company_id port good side quantity_mode quantity filled limit budget spent onward status reason created_ms)a
  defstruct @fields
  def from_row(row), do: struct!(__MODULE__, Map.new(@fields, &{&1, row[Atom.to_string(&1)]}))

  def to_row(%__MODULE__{} = order),
    do: Map.new(@fields, &{Atom.to_string(&1), Map.fetch!(order, &1)})

  def record_fill(%__MODULE__{} = order, quantity, spent) do
    if order.status not in ["planned", "waiting"] or quantity < 1 or
         quantity > order.quantity - order.filled or spent < 0 or
         (order.budget != nil and order.spent + spent > order.budget),
       do:
         raise(
           ArgumentError,
           "Fill exceeds active order: status=#{order.status} fill=#{quantity} remaining=#{order.quantity - order.filled} spent=#{spent} prior=#{order.spent} budget=#{inspect(order.budget)}"
         )

    filled = order.filled + quantity

    target =
      if order.quantity_mode == "maximum" and quantity < 10_000, do: filled, else: order.quantity

    %{
      order
      | filled: filled,
        spent: order.spent + spent,
        quantity: target,
        status: if(filled == target, do: "filled", else: "waiting"),
        reason: if(filled == target, do: "Target filled", else: "Waiting for handling to finish")
    }
  end
end
