defmodule TijaraTides.Domain.State do
  @moduledoc "Internal world-state access. Mutation helpers do not replace business operations or validation."

  defdelegate entities(state, kind), to: TijaraTides.Domain.ReadState
  defdelegate owned(state, kind, field, owner), to: TijaraTides.Domain.ReadState
  defdelegate get(state, kind, id), to: TijaraTides.Domain.ReadState

  def put(state, kind, id, value) do
    if get(state, kind, id) == value do
      state
    else
      %{
        state
        | entities: Map.update(state.entities, kind, %{id => value}, &Map.put(&1, id, value))
      }
      |> TijaraTides.Domain.EntityIndex.update(kind, id, get(state, kind, id), value)
      |> TijaraTides.Domain.ChangeSet.record(kind, id, :put)
    end
  end

  def delete(state, kind, id) do
    if kind == "companies" and
         Enum.any?(entities(state, "ships"), fn {_, ship} -> ship["company_id"] == id end),
       do: raise(ArgumentError, "retire or transfer ships before removing a company")

    if Map.has_key?(entities(state, kind), id) do
      %{state | entities: Map.update!(state.entities, kind, &Map.delete(&1, id))}
      |> TijaraTides.Domain.EntityIndex.update(kind, id, get(state, kind, id), nil)
      |> TijaraTides.Domain.ChangeSet.record(kind, id, :delete)
    else
      state
    end
  end

  @doc "Reconstitute a durable row into the cache without declaring a database write."
  def cache(state, kind, id, row) do
    %{state | entities: Map.update(state.entities, kind, %{id => row}, &Map.put(&1, id, row))}
    |> TijaraTides.Domain.EntityIndex.update(kind, id, get(state, kind, id), row)
  end

  def evict(state, kind, id) do
    row = get(state, kind, id)

    %{state | entities: Map.update(state.entities, kind, %{}, &Map.delete(&1, id))}
    |> TijaraTides.Domain.EntityIndex.update(kind, id, row, nil)
  end
end
