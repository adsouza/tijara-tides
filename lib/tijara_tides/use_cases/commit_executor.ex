defmodule TijaraTides.UseCases.CommitExecutor do
  @moduledoc "One atomic acceptance path for player commands, lifecycle operations and world ticks."
  alias TijaraTides.UseCases.{CommitPreparation, CommandResult}

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
