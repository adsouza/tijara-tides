defmodule TijaraTides.Domain.PortCargoMarket.Batch do
  @moduledoc "A supplier freshness lot."
  @enforce_keys [:lot_id, :quantity, :expires_ms]
  defstruct @enforce_keys
end
