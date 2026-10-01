defmodule TijaraTides.Domain.Ship.VisitPlan do
  @moduledoc "Typed visit plan; persisted fields are decoded explicitly."
  @fields ~w(id ship_id company_id port onward auto_depart departure_wait)a
  @enforce_keys @fields
  @all_fields @fields ++ [:advance_budget]
  defstruct @fields ++ [advance_budget: nil]
  @type t :: %__MODULE__{}
  def from_row(nil), do: nil
  def from_row(%__MODULE__{} = child), do: validate!(child)

  def from_row(row) do
    unknown = Map.keys(row) -- Enum.map(@all_fields, &Atom.to_string/1)
    if unknown != [], do: raise(ArgumentError, "Unknown visit_plan fields: #{inspect(unknown)}")

    row = Map.put_new(row, "advance_budget", nil)

    struct!(__MODULE__, Map.new(@all_fields, &{&1, Map.fetch!(row, Atom.to_string(&1))}))
    |> validate!()
  end

  def to_row(%__MODULE__{} = child) do
    validate!(child)
    Map.new(@all_fields, &{Atom.to_string(&1), Map.fetch!(child, &1)})
  end

  defp validate!(child) do
    unless is_boolean(child.auto_depart) and is_binary(child.port) and is_binary(child.onward),
      do: raise(ArgumentError, "Invalid onward plan")

    child
  end
end
