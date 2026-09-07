defmodule TijaraTides.Domain.Journal do
  @moduledoc "Pure accounting events. Positive amounts are debits; negative amounts are credits."

  def post(state, company, kind, entries, context \\ %{}) do
    entries = Enum.reject(entries, fn {_, amount} -> amount == 0 end)

    if Enum.sum(Enum.map(entries, &elem(&1, 1))) != 0,
      do: raise(ArgumentError, "Unbalanced journal event")

    if entries == [] do
      state
    else
      event = %{
        company: company,
        kind: kind,
        clock_ms: state.clock_ms,
        entries: entries,
        ship: context[:ship],
        good: context[:good]
      }

      Map.update(state, :journal, [event], &(&1 ++ [event]))
    end
  end

  def clear(state), do: Map.drop(state, [:journal, :new_lots])
end
