defmodule TijaraTides.Domain.EntityIndex do
  @moduledoc "Derived ownership lookup for bounded company operations; rebuilt on world load, never persisted."
  @fields ~w(company_id borrower_company_id account_id inviter sponsor_id beneficiary_id ship_id stop_id token_hash email requester purpose status)
  def fields, do: @fields

  def rebuild(state) do
    index =
      for {kind, rows} <- state.entities, {id, row} <- rows, reduce: %{} do
        index -> add(index, kind, id, row)
      end

    Map.put(state, :entity_index, index)
  end

  def update(%{entity_index: index} = state, kind, id, before, after_row) do
    index =
      Enum.reduce(@fields, index, fn field, acc ->
        if before && before[field] do
          key = {kind, field, before[field]}
          remaining = Map.get(acc, key, MapSet.new()) |> MapSet.delete(id)

          if MapSet.size(remaining) == 0,
            do: Map.delete(acc, key),
            else: Map.put(acc, key, remaining)
        else
          acc
        end
      end)

    Map.put(state, :entity_index, if(after_row, do: add(index, kind, id, after_row), else: index))
  end

  def update(state, _kind, _id, _before, _after), do: state

  defp add(index, kind, id, row) do
    Enum.reduce(@fields, index, fn field, acc ->
      if row[field],
        do: Map.update(acc, {kind, field, row[field]}, MapSet.new([id]), &MapSet.put(&1, id)),
        else: acc
    end)
  end
end
