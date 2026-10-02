defmodule TijaraTides.Domain.Ship.RouteTarget do
  @moduledoc "Typed route target; persisted fields are decoded explicitly."
  @fields ~w(id ship_id company_id stop_id side good quantity_mode quantity limit budget min_remaining_ms linked_warehouse_id)a
  @enforce_keys @fields -- [:min_remaining_ms, :linked_warehouse_id]
  defstruct (@fields -- [:min_remaining_ms, :linked_warehouse_id]) ++
              [min_remaining_ms: 0, linked_warehouse_id: nil]

  @type t :: %__MODULE__{}
  def from_row(nil), do: nil
  def from_row(%__MODULE__{} = child), do: validate!(child)

  def from_row(row) do
    unknown = Map.keys(row) -- Enum.map(@fields, &Atom.to_string/1)
    if unknown != [], do: raise(ArgumentError, "Unknown route_target fields: #{inspect(unknown)}")

    row = row |> Map.put_new("min_remaining_ms", 0) |> Map.put_new("linked_warehouse_id", nil)

    struct!(__MODULE__, Map.new(@fields, &{&1, Map.fetch!(row, Atom.to_string(&1))}))
    |> validate!()
  end

  def to_row(%__MODULE__{} = child) do
    validate!(child)
    Map.new(@fields, &{Atom.to_string(&1), Map.fetch!(child, &1)})
  end

  defp validate!(child) do
    unless child.side in ["buy", "sell"] and
             (is_nil(child.linked_warehouse_id) or
                (child.side == "buy" and child.quantity_mode == "fixed" and
                   is_binary(child.linked_warehouse_id))) and
             child.quantity_mode in ["fixed", "maximum"] and
             (child.quantity_mode == "maximum" or
                (is_integer(child.quantity) and child.quantity in 1..10_000)) and
             is_integer(child.limit) and child.limit >= 0 and
             (is_nil(child.budget) or (is_integer(child.budget) and child.budget > 0)) and
             TijaraTides.Domain.CargoRules.valid_remaining?(child.min_remaining_ms) and
             (child.side == "buy" or child.min_remaining_ms == 0),
           do: raise(ArgumentError, "Invalid route target")

    child
  end
end
