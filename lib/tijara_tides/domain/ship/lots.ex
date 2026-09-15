defmodule TijaraTides.Domain.Ship.Lots do
  @moduledoc "Scoped clock and lot allocation inputs for ship cargo transitions."
  @enforce_keys [:clock_ms]
  defstruct [:clock_ms, lot_allocation: {:local, 1}, new_lots: []]
end
