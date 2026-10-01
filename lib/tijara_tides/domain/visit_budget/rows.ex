defmodule TijaraTides.Domain.VisitBudget.Rows do
  @moduledoc "Closed codec for the existing durable visit budget row."
  alias TijaraTides.Domain.VisitBudget
  @fields ~w(id company_id ship_id stop_id port amount remaining strict skip visit)a
  def decode(row) do
    keys = Enum.map(@fields, &Atom.to_string/1)
    unless Map.keys(row) -- keys == [], do: raise(ArgumentError, "Unknown visit_budget fields")
    struct!(VisitBudget, Map.new(@fields, &{&1, Map.fetch!(row, Atom.to_string(&1))}))
  end

  def encode(%VisitBudget{} = model),
    do: Map.new(@fields, &{Atom.to_string(&1), Map.fetch!(model, &1)})
end
