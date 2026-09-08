defmodule TijaraTides.Domain.State do
  @moduledoc "Internal world-state access. Mutation helpers do not replace business operations or validation."

  defdelegate entities(state, kind), to: TijaraTides.Domain.ReadState
  defdelegate get(state, kind, id), to: TijaraTides.Domain.ReadState

  def put(state, kind, id, value),
    do: %{
      state
      | entities: Map.update(state.entities, kind, %{id => value}, &Map.put(&1, id, value))
    }

  def delete(state, "companies", id) do
    if Enum.any?(entities(state, "ships"), fn {_, ship} -> ship["company_id"] == id end),
      do: raise(ArgumentError, "retire or transfer ships before removing a company")

    %{state | entities: Map.update(state.entities, "companies", %{}, &Map.delete(&1, id))}
  end

  def delete(state, kind, id),
    do: %{state | entities: Map.update(state.entities, kind, %{}, &Map.delete(&1, id))}
end
