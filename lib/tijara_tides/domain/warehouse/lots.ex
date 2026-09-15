defmodule TijaraTides.Domain.Warehouse.Lots do
  @moduledoc "Scoped clock and lot allocator for warehouse cargo transitions."
  @enforce_keys [:clock_ms]
  defstruct [:clock_ms, lot_allocation: {:local, 1}, new_lots: []]
end
