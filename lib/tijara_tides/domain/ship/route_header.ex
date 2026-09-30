defmodule TijaraTides.Domain.Ship.RouteHeader do
  @moduledoc "Typed route header; persisted fields are decoded explicitly."
  @fields ~w(id ship_id company_id status cursor visit phase auto_depart stop_after reason)a
  @wait_defaults [visit_arrived_ms: nil, wait_deadline_ms: nil, wait_timed_out: false]
  @all_fields @fields ++ Keyword.keys(@wait_defaults)
  @enforce_keys @fields
  defstruct @fields ++ @wait_defaults
  @type t :: %__MODULE__{}
  def from_row(nil), do: nil
  def from_row(%__MODULE__{} = child), do: validate!(child)

  def from_row(row) do
    unknown = Map.keys(row) -- Enum.map(@all_fields, &Atom.to_string/1)
    if unknown != [], do: raise(ArgumentError, "Unknown route_header fields: #{inspect(unknown)}")

    row = Map.merge(Map.new(@wait_defaults, fn {k, v} -> {Atom.to_string(k), v} end), row)

    struct!(__MODULE__, Map.new(@all_fields, &{&1, Map.fetch!(row, Atom.to_string(&1))}))
    |> validate!()
  end

  def to_row(%__MODULE__{} = child) do
    validate!(child)
    Map.new(@all_fields, &{Atom.to_string(&1), Map.fetch!(child, &1)})
  end

  defp validate!(child) do
    unless child.status in ["draft", "running", "paused"] and
             child.phase in ["arrival", "selling", "buying"] and is_integer(child.cursor) and
             child.cursor >= 0 and is_integer(child.visit) and child.visit >= 0 and
             is_boolean(child.auto_depart) and is_boolean(child.stop_after) and
             is_boolean(child.wait_timed_out) and
             (is_nil(child.visit_arrived_ms) or
                (is_integer(child.visit_arrived_ms) and child.visit_arrived_ms >= 0)) and
             (is_nil(child.wait_deadline_ms) or
                (is_integer(child.visit_arrived_ms) and is_integer(child.wait_deadline_ms) and
                   child.wait_deadline_ms > child.visit_arrived_ms)),
           do: raise(ArgumentError, "Invalid route state")

    child
  end
end
