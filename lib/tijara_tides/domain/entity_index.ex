defmodule TijaraTides.Domain.EntityIndex do
  @moduledoc "Derived ownership lookup for bounded company operations; rebuilt on world load, never persisted."
  # Only fields with an `owned/4` reader belong here: every entry costs a MapSet
  # update on each row mutation and a bucket per distinct value on rebuild.
  @fields ~w(guarantee_id company_id borrower_company_id account_id inviter token_hash email requester)

  # Derived keys are computed from a row rather than read off it, so a lookup can be
  # narrower than any stored column. A company's closed loans are history that nothing
  # per-command acts on, and keeping them out of this key is what stops every command
  # paying for every loan the company has ever taken.
  @derived ~w(open_company_id)
  @all @fields ++ @derived
  def fields, do: @all

  # `:none`, not nil, when a derived key does not apply: a stored field's nil is a real
  # value that a nil owner legitimately matches, while a key that does not apply to a
  # row must match nothing at all.
  def value("loans", "open_company_id", row),
    do: if(row["status"] == "open", do: row["company_id"], else: :none)

  def value(_kind, field, row), do: row[field]

  def rebuild(state) do
    index =
      for {kind, rows} <- state.entities, {id, row} <- rows, reduce: %{} do
        index -> add(index, kind, id, row)
      end

    Map.put(state, :entity_index, index)
  end

  def update(%{entity_index: index} = state, kind, id, before, after_row) do
    index =
      Enum.reduce(@all, index, fn field, acc ->
        case before && value(kind, field, before) do
          absent when absent in [nil, :none] ->
            acc

          previous ->
            key = {kind, field, previous}
            remaining = Map.get(acc, key, MapSet.new()) |> MapSet.delete(id)

            if MapSet.size(remaining) == 0,
              do: Map.delete(acc, key),
              else: Map.put(acc, key, remaining)
        end
      end)

    Map.put(state, :entity_index, if(after_row, do: add(index, kind, id, after_row), else: index))
  end

  def update(state, _kind, _id, _before, _after), do: state

  defp add(index, kind, id, row) do
    Enum.reduce(@all, index, fn field, acc ->
      case value(kind, field, row) do
        absent when absent in [nil, :none] -> acc
        value -> Map.update(acc, {kind, field, value}, MapSet.new([id]), &MapSet.put(&1, id))
      end
    end)
  end
end
