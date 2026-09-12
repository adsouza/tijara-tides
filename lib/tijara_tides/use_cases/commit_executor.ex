defmodule TijaraTides.UseCases.CommitExecutor do
  @moduledoc "One atomic acceptance path for player commands, lifecycle operations and world ticks."
  alias TijaraTides.UseCases.{CommitPreparation, CommandResult}

  @doc "Retry market conflicts twice from a fresh, fenced snapshot; never retry a stale plan."
  def replan(game, store, operation), do: replan(game, store, operation, 2, false)

  defp replan(game, {store, storage} = port, operation, remaining, refreshed?) do
    case operation.(game) do
      {:halt, :market_conflict} ->
        case store.reload(storage, game) do
          {:ok, fresh} ->
            fresh = TijaraTides.Domain.ReadState.rebuild_notice_index(fresh)

            if remaining > 0,
              do: replan(fresh, port, operation, remaining - 1, true),
              else: {:error, :market_busy, fresh}

          {:error, reason} ->
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
    changed = CommitPreparation.prepare(before, %{changed | revision: before.revision + 1})

    case store.commit(storage, before, changed, receipt) do
      {:ok, :ok} -> outcome(CommitPreparation.accepted(changed, wall_ms), decorate.(result), true)
      {:error, {:replay, result}} -> outcome(before, decorate.(result), false)
      {:error, reason} -> {:halt, reason}
    end
  end

  def restore(game, operation, {store, storage}), do: store.restore(storage, game, operation)

  def outcome(game, reply, committed?),
    do: {:ok, %CommandResult{game: game, reply: reply, committed?: committed?}}
end
