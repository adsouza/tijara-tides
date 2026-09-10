defmodule TijaraTides.UseCases.CommitPreparation do
  @moduledoc "Apply accounting projections once before an atomic commit; discard pending events only after success."
  alias TijaraTides.Domain.{Journal, Reporting}

  def prepare(before, changed) do
    target_clock = changed.clock_ms
    previous = Map.get(before, :journal, [])
    pending = Map.get(changed, :journal, [])

    unless Enum.take(pending, length(previous)) == previous,
      do: raise(ArgumentError, "Pending journal history changed")

    events = Enum.drop(pending, length(previous))
    # Establish a baseline before any journal delta, including when restoring an old world.
    baseline = Reporting.initialize(before)

    adjustments =
      Enum.reduce(events, %{}, fn event, totals ->
        Map.update(
          totals,
          event.company,
          Reporting.asset_delta(event.entries),
          &(&1 + Reporting.asset_delta(event.entries))
        )
      end)

    changed = Reporting.initialize(changed, adjustments)

    entities =
      Enum.reduce(["reporting_accounts", "financial_reports"], changed.entities, fn kind, rows ->
        Map.put(
          rows,
          kind,
          Map.merge(Map.get(rows, kind, %{}), Map.get(baseline.entities, kind, %{}))
        )
      end)

    changed = %{changed | entities: entities}

    changed =
      Enum.reduce(events, changed, fn event, state ->
        # Reporting accrues to each event's authoritative journal timestamp.
        state = %{state | clock_ms: event.clock_ms}
        Reporting.post(state, event.company, event.entries)
      end)

    Reporting.advance(%{changed | clock_ms: target_clock})
  end

  def accepted(game), do: game |> Journal.clear() |> Reporting.compact()
end
