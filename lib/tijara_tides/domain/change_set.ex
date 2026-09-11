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

  def accepted(state), do: Map.put(state, :changes, %{})
end
