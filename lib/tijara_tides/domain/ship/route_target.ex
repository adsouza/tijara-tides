defmodule TijaraTides.Domain.Ship.RouteTarget do
  @moduledoc "Typed route target; persisted fields are decoded explicitly."
  @fields ~w(id ship_id company_id stop_id side good quantity_mode quantity limit budget)a
  @enforce_keys @fields
  defstruct @fields
  @type t :: %__MODULE__{}
  def from_row(nil), do: nil
  def from_row(%__MODULE__{} = child), do: validate!(child)

  def from_row(row) do
    unknown = Map.keys(row) -- Enum.map(@fields, &Atom.to_string/1)
    if unknown != [], do: raise(ArgumentError, "Unknown route_target fields: #{inspect(unknown)}")

    struct!(__MODULE__, Map.new(@fields, &{&1, Map.fetch!(row, Atom.to_string(&1))}))
    |> validate!()
  end

  def to_row(%__MODULE__{} = child) do
    validate!(child)
    Map.new(@fields, &{Atom.to_string(&1), Map.fetch!(child, &1)})
  end

  defp validate!(child) do
    unless child.side in ["buy", "sell"] and child.quantity_mode in ["fixed", "maximum"] and
             (child.quantity_mode == "maximum" or
                (is_integer(child.quantity) and child.quantity in 1..10_000)) and
             is_integer(child.limit) and child.limit >= 0 and
             (is_nil(child.budget) or (is_integer(child.budget) and child.budget > 0)),
           do: raise(ArgumentError, "Invalid route target")

    child
  end
end
