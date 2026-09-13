defmodule TijaraTides.Domain.BerthFixture do
  @moduledoc """
  Explicit persisted berth fixtures, including intermediate states for isolated tests.
  Writes go through the ship aggregate's own row encoding, so a fixture can only build
  states the domain could have produced — a raw merge would leave nil berth keys that
  Ship.to_row/1 drops and a reload never returns.
  """
  alias TijaraTides.Domain.{Ship, State}

  def update(state, id, fields) do
    ship =
      State.get(state, "ships", id)
      |> Ship.from_row()
      |> then(&Enum.reduce(fields, &1, fn {key, value}, acc -> Map.replace!(acc, key, value) end))

    State.put(state, "ships", id, Ship.to_row(ship))
  end
end
