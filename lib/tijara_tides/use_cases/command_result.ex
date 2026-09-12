defmodule TijaraTides.UseCases.CommandResult do
  @moduledoc "Committed or replayed result. A refreshed result carries a durable snapshot, not a new local commit."
  @enforce_keys [:game, :reply, :committed?]
  defstruct [:game, :reply, :committed?, refreshed?: false]
end
