defmodule TijaraTides.UseCases.CommitExecutor do
  @moduledoc "One atomic acceptance path for player commands, lifecycle operations and world ticks."
  alias TijaraTides.UseCases.{CommitPreparation, CommandResult, Observation}

  @doc "Retry market conflicts twice from a fresh, fenced snapshot; never retry a stale plan."
  def replan(game, store, operation), do: replan(game, store, operation, 2, false)

  defp replan(game, {store, storage} = port, operation, remaining, refreshed?) do
    case operation.(game) do
      {:halt, :market_conflict} ->
        case store.reload(storage, game) do
          {:ok, fresh} ->
            fresh = TijaraTides.Domain.ReadState.rebuild_notice_index(fresh)

            if remaining > 0 do
              TijaraTides.UseCases.Observation.record(:conflict_retry)
              replan(fresh, port, operation, remaining - 1, true)
            else
              TijaraTides.UseCases.Observation.record(:conflict_exhausted)
              {:error, :market_busy, fresh}
            end

          {:error, reason} ->
            TijaraTides.UseCases.Observation.record(:conflict_reload_failed)
            {:halt, reason}
        end

      {:error, reason} when refreshed? ->
        {:error, reason, game}

      {:ok, %CommandResult{} = result} when refreshed? ->
        {:ok, %{result | refreshed?: true}}

      result ->
        result
    end
  end

  def commit(before, changed, result, receipt, {store, storage}, decorate \\ & &1, wall_ms \\ nil) do
    changed =
      Observation.measure(:prepare_commit, fn ->
        CommitPreparation.prepare(before, %{changed | revision: before.revision + 1})
      end)

    case Observation.measure(:persist, fn -> store.commit(storage, before, changed, receipt) end) do
      {:ok, :ok} ->
        accepted =
          Observation.measure(:accept_commit, fn ->
            CommitPreparation.accepted(changed, wall_ms)
          end)

        outcome(accepted, decorate.(result), true)

      {:error, {:replay, result}} ->
        outcome(before, decorate.(result), false)

      {:error, reason} ->
        {:halt, reason}
    end
  end

  def restore(game, operation, {store, storage}), do: store.restore(storage, game, operation)

  def outcome(game, reply, committed?),
    do: {:ok, %CommandResult{game: game, reply: reply, committed?: committed?}}
end
