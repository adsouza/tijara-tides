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

  @impl true
  def restore(context, game, operation) do
    keys =
      case operation do
        {:seed, hash} ->
          [{"invitations", hash, "id"}]

        {:redeem, hash, device} ->
          [
            {"invitations", hash, "id"},
            {"sessions", device, "id"},
            {"email_requests", hash, "token_hash"}
          ]

        {:email_request, _, _, _} ->
          []

        {:email_request_id, id} ->
          [{"email_requests", id, "id"}]

        {:email_redeem, hash, device, _} ->
          [
            {"email_requests", hash, "token_hash"},
            {"invitations", hash, "id"},
            {"sessions", device, "id"}
          ]

        {action, id} when action in [:email_failed, :email_delivered] ->
          [{"email_requests", id, "id"}]

        _ ->
          []
      end

    Enum.reduce(keys, game, fn {kind, value, field}, game ->
      cached =
        if field == "id",
          do: TijaraTides.Domain.ReadState.get(game, kind, value),
          else: List.first(TijaraTides.Domain.ReadState.owned(game, kind, field, value))

      if cached != nil or value == nil do
        game
      else
        case TijaraTides.Infrastructure.Persistence.GameRows.lookup(
               context.repo,
               context.world_id,
               kind,
               value,
               field
             ) do
          nil -> game
          {id, row} -> TijaraTides.Domain.Account.restore_history(game, kind, id, row)
        end
      end
    end)
  end
end
