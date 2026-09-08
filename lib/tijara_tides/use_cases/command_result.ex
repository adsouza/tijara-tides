defmodule TijaraTides.UseCases.CommandResult do
  @moduledoc "Committed or replayed application result; publication is allowed only for committed changes."
  @enforce_keys [:game, :reply, :committed?]
  defstruct [:game, :reply, :committed?]
end
