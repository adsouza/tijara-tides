defmodule TijaraTides.Domain.ReadState do
  @moduledoc "Read-only access to authoritative state for application projections."
  def entities(state, kind), do: Map.get(state.entities, kind, %{})
  def get(state, kind, id), do: entities(state, kind)[id]
end
