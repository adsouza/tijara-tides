defmodule TijaraTides.Domain.ReadState do
  @moduledoc "Read-only access to authoritative state for application projections."
  def entities(state, kind), do: Map.get(state.entities, kind, %{})
  def get(state, kind, id), do: entities(state, kind)[id]

  def owned(state, kind, field, owner) do
    case if(field in ["company_id", "borrower_company_id"],
           do: Map.fetch(state, :entity_index),
           else: :error
         ) do
      {:ok, index} ->
        Map.get(index, {kind, field, owner}, MapSet.new())
        |> Enum.sort()
        |> Enum.map(&get(state, kind, &1))

      :error ->
        entities(state, kind) |> Map.values() |> Enum.filter(&(&1[field] == owner))
    end
  end
end
