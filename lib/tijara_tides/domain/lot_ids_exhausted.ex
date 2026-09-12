defmodule TijaraTides.Domain.LotIdsExhausted do
  @moduledoc "Signals that a pure operation needs a larger supplied lot identity batch."
  defexception message: "Lot identity batch exhausted"
end
