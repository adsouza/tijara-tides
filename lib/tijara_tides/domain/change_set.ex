defmodule TijaraTides.Domain.ChangeSet do
  @moduledoc "Explicit row mutations within a world transaction; cache eviction is not deletion."

  def record(state, kind, id, operation) when operation in [:put, :delete] do
    sequence = Map.get(state, :mutation_sequence, 0) + 1

    state
    |> Map.put(:mutation_sequence, sequence)
    |> Map.update(
      :changes,
      %{{kind, id} => {sequence, operation}},
      &Map.put(&1, {kind, id}, {sequence, operation})
    )
  end

  def since(before, after_state) do
    baseline = Map.get(before, :mutation_sequence, 0)

    for {{kind, id}, {sequence, operation}} <- Map.get(after_state, :changes, %{}),
        sequence > baseline,
        into: %{},
        do: {{kind, id}, operation}
  end

  def affected_companies(before, after_state) do
    rows =
      for {{kind, id}, _} <- since(before, after_state),
          state <- [before, after_state],
          row = get_in(state, [:entities, kind, id]),
          row != nil do
        if kind in ["companies", "reporting_accounts"],
          do: [id],
          else: [row["company_id"], row["borrower_company_id"]]
      end

    previous = Map.get(before, :journal, [])
    events = Map.get(after_state, :journal, []) |> Enum.drop(length(previous))

    (List.flatten(rows) ++ Enum.map(events, & &1.company))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  def accepted(state), do: Map.put(state, :changes, %{})
end
