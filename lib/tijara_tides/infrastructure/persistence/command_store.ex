defmodule TijaraTides.Infrastructure.Persistence.CommandStore do
  @moduledoc "PostgreSQL adapter for the application command transaction port."
  @behaviour TijaraTides.UseCases.CommandStore
  alias TijaraTides.Infrastructure.Persistence.GameStore

  @impl true
  def receipt(%{repo: repo, world_id: world}, account, request, fingerprint),
    do: GameStore.receipt(repo, world, account, request, fingerprint)

  @impl true
  def commit(%{repo: repo, world_id: world}, before, after_state, receipt),
    do: GameStore.commit(repo, world, before.epoch, before, after_state, receipt)
end
