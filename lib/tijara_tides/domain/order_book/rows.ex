defmodule TijaraTides.Domain.OrderBook.Rows do
  @moduledoc "Codec for the unchanged persisted order representation."
  alias TijaraTides.Domain.OrderBook

  @fields ~w(id company_id warehouse_id port good side quantity price priority_ms priority_seq expires_ms)a
  def decode(row) do
    unknown = Map.keys(row) -- Enum.map(@fields, &Atom.to_string/1)
    if unknown != [], do: raise(ArgumentError, "Unknown order fields: #{inspect(unknown)}")

    struct!(OrderBook, Map.new(@fields, &{&1, Map.fetch!(row, Atom.to_string(&1))}))
  end

  def encode(%OrderBook{} = order),
    do: Map.new(@fields, &{Atom.to_string(&1), Map.fetch!(order, &1)})
end
