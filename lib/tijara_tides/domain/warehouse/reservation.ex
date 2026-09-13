defmodule TijaraTides.Domain.Warehouse.Reservation do
  @moduledoc "A ship's claim to owned stock or receiving volume, managed by its warehouse root."
  @fields ~w(id warehouse_id company_id ship_id good kind quantity created_ms stop_id)a
  @enforce_keys @fields
  defstruct @fields

  def from_row(row) do
    if Map.keys(row) -- Enum.map(@fields, &Atom.to_string/1) != [],
      do: raise(ArgumentError, "Unknown warehouse reservation fields")

    struct!(__MODULE__, Map.new(@fields, &{&1, Map.fetch!(row, Atom.to_string(&1))}))
  end

  def to_row(r), do: Map.new(@fields, &{Atom.to_string(&1), Map.fetch!(r, &1)})
end
