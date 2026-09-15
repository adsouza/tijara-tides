defmodule TijaraTides.Domain.BerthFixture do
  @moduledoc """
  Explicit persisted berth fixtures, including intermediate states for isolated tests.
  Writes go through the ship aggregate's own row encoding, so a fixture can only build
  states the domain could have produced — a raw merge would leave nil berth keys that
  Ship.Rows.encode/1 drops and a reload never returns.
  """
  alias TijaraTides.Domain.{Ship, State}

  def update(state, id, fields) do
    ship =
      State.get(state, "ships", id)
      |> Ship.Rows.decode()
      |> then(&Enum.reduce(fields, &1, fn {key, value}, acc -> Map.replace!(acc, key, value) end))

    State.put(state, "ships", id, Ship.Rows.encode(ship))
  end
end
