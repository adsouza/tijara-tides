defmodule TijaraTides.Domain.Ship.RouteStop do
  @moduledoc "Typed route stop; persisted fields are decoded explicitly."
  @fields ~w(id ship_id company_id position port)a
  @enforce_keys @fields
  defstruct @fields
  @type t :: %__MODULE__{}
  def from_row(nil), do: nil
  def from_row(%__MODULE__{} = child), do: validate!(child)

  def from_row(row) do
    unknown = Map.keys(row) -- Enum.map(@fields, &Atom.to_string/1)
    if unknown != [], do: raise(ArgumentError, "Unknown route_stop fields: #{inspect(unknown)}")

    struct!(__MODULE__, Map.new(@fields, &{&1, Map.fetch!(row, Atom.to_string(&1))}))
    |> validate!()
  end

  def to_row(%__MODULE__{} = child) do
    validate!(child)
    Map.new(@fields, &{Atom.to_string(&1), Map.fetch!(child, &1)})
  end

  defp validate!(child) do
    unless is_integer(child.position) and child.position in 0..7 and is_binary(child.port),
      do: raise(ArgumentError, "Invalid route stop")

    child
  end
end
