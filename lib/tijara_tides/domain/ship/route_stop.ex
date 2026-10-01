defmodule TijaraTides.Domain.Ship.RouteStop do
  @moduledoc "Typed route stop; persisted fields are decoded explicitly."
  @fields ~w(id ship_id company_id position port)a
  @all_fields @fields ++ [:max_wait_ms, :advance_budget]
  @enforce_keys @fields
  defstruct @fields ++ [max_wait_ms: nil, advance_budget: nil]
  def max_wait_ms, do: 30 * 86_400_000
  @type t :: %__MODULE__{}
  def from_row(nil), do: nil
  def from_row(%__MODULE__{} = child), do: validate!(child)

  def from_row(row) do
    unknown = Map.keys(row) -- Enum.map(@all_fields, &Atom.to_string/1)
    if unknown != [], do: raise(ArgumentError, "Unknown route_stop fields: #{inspect(unknown)}")

    row = row |> Map.put_new("max_wait_ms", nil) |> Map.put_new("advance_budget", nil)

    struct!(__MODULE__, Map.new(@all_fields, &{&1, Map.fetch!(row, Atom.to_string(&1))}))
    |> validate!()
  end

  def to_row(%__MODULE__{} = child) do
    validate!(child)
    Map.new(@all_fields, &{Atom.to_string(&1), Map.fetch!(child, &1)})
  end

  defp validate!(child) do
    unless is_integer(child.position) and child.position in 0..7 and is_binary(child.port) and
             (is_nil(child.advance_budget) or
                (is_integer(child.advance_budget) and child.advance_budget in 0..1_000_000_000_000)) and
             (is_nil(child.max_wait_ms) or
                (is_integer(child.max_wait_ms) and child.max_wait_ms in 1..max_wait_ms())),
           do: raise(ArgumentError, "Invalid route stop")

    child
  end
end
