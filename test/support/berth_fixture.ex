defmodule TijaraTides.Domain.BerthFixture do
  @moduledoc "Explicit persisted berth fixtures, including intermediate states for isolated tests."
  def update(state, id, fields) do
    ship = TijaraTides.Domain.State.get(state, "ships", id)
    row = Map.merge(ship, Map.new(fields, fn {key, value} -> {Atom.to_string(key), value} end))
    TijaraTides.Domain.State.put(state, "ships", id, row)
  end
end
