defmodule TijaraTides.Domain.LiquidationPool.Rows do
  @moduledoc "Closed codec for the existing durable liquidation pool row."
  alias TijaraTides.Domain.LiquidationPool

  @fields ~w(id company_id port status expires_ms grace_end_ms last_ms original_blocks occupied_blocks rent duration_ms surcharge_bps window_ms clearance_bps handling_rate rent_due rent_remainder handling_due clearance_remainders proceeds charged paid sunk completed_ms replacement_paid)a
  def decode(row) do
    row = Map.put_new(row, "replacement_paid", 0)
    keys = Enum.map(@fields, &Atom.to_string/1)

    unless Map.keys(row) -- keys == [],
      do: raise(ArgumentError, "Unknown liquidation_pool fields")

    struct!(LiquidationPool, Map.new(@fields, &{&1, Map.fetch!(row, Atom.to_string(&1))}))
  end

  def encode(%LiquidationPool{} = model),
    do: Map.new(@fields, &{Atom.to_string(&1), Map.fetch!(model, &1)})
end
