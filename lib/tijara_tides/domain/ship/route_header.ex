defmodule TijaraTides.Domain.Ship.RouteHeader do
  @moduledoc "Typed route header; persisted fields are decoded explicitly."
  @fields ~w(id ship_id company_id status cursor visit phase auto_depart stop_after reason)a
  @enforce_keys @fields
  defstruct @fields
  @type t :: %__MODULE__{}
  def from_row(nil), do: nil
  def from_row(%__MODULE__{} = child), do: validate!(child)

  def from_row(row) do
    unknown = Map.keys(row) -- Enum.map(@fields, &Atom.to_string/1)
    if unknown != [], do: raise(ArgumentError, "Unknown route_header fields: #{inspect(unknown)}")

    struct!(__MODULE__, Map.new(@fields, &{&1, Map.fetch!(row, Atom.to_string(&1))}))
    |> validate!()
  end

  def to_row(%__MODULE__{} = child) do
    validate!(child)
    Map.new(@fields, &{Atom.to_string(&1), Map.fetch!(child, &1)})
  end

  defp validate!(child) do
    unless child.status in ["draft", "running", "paused"] and
             child.phase in ["arrival", "selling", "buying"] and is_integer(child.cursor) and
             child.cursor >= 0 and is_integer(child.visit) and child.visit >= 0 and
             is_boolean(child.auto_depart) and is_boolean(child.stop_after),
           do: raise(ArgumentError, "Invalid route state")

    child
  end
end
