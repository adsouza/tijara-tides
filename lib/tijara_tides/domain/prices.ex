defmodule TijaraTides.Domain.Prices do
  @moduledoc "Bounds shared by player-entered prices."

  # Every player price and limit fits this many cents; the bound keeps widened
  # and summed values inside PostgreSQL bigint columns.
  @max_cents 1_000_000_000_000
  def max_cents, do: @max_cents
end
