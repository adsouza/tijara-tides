defmodule TijaraTides.Domain.CargoLots.Scope do
  @moduledoc "Scoped clock and lot allocation inputs shared by the roots that split cargo."
  @enforce_keys [:clock_ms]
  defstruct [:clock_ms, lot_allocation: {:local, 1}, new_lots: []]
end
