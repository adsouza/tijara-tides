defmodule TijaraTides.Domain.OrderBook.Rows do
  @moduledoc "Codec for the unchanged persisted order representation."
  alias TijaraTides.Domain.OrderBook

  @fields ~w(id company_id warehouse_id port good side quantity price priority_ms priority_seq expires_ms)a
  @defaults [
    min_grade: 0,
    min_remaining_ms: 0,
    initial_price: nil,
    markdowns: nil,
    price_floor: 0,
    portions: %{}
  ]
  def decode(row) do
    unknown = Map.keys(row) -- Enum.map(@fields ++ Keyword.keys(@defaults), &Atom.to_string/1)
    if unknown != [], do: raise(ArgumentError, "Unknown order fields: #{inspect(unknown)}")

    struct!(
      OrderBook,
      Map.new(@fields, &{&1, Map.fetch!(row, Atom.to_string(&1))})
      |> Map.merge(Map.new(@defaults, fn {k, v} -> {k, Map.get(row, Atom.to_string(k), v)} end))
    )
  end

  def encode(%OrderBook{} = order),
    do:
      Map.new(@fields, &{Atom.to_string(&1), Map.fetch!(order, &1)})
      |> Map.merge(
        Map.new(
          for {key, default} <- @defaults,
              Map.fetch!(order, key) != default,
              do: {Atom.to_string(key), Map.fetch!(order, key)}
        )
      )
end
