defmodule TijaraTides.UseCases.LifecycleCommands do
  @moduledoc "Identity and simulation workflows with explicit credentials, time and atomic persistence."
  alias TijaraTides.Domain.{Account, EmailIdentity, Game, ReadState}
  alias TijaraTides.UseCases.CommitExecutor

  def run(game, operation, context, store) do
    # Preserve the original target clock: reloading must not advance elapsed time twice.
    target =
      case operation do
        {:advance, elapsed} -> game.clock_ms + elapsed
        _ -> nil
      end

    CommitExecutor.replan(game, store, fn fresh ->
      planned = if target, do: {:advance, max(0, target - fresh.clock_ms)}, else: operation
      run_once(fresh, planned, context, store)
    end)
  end

  defp run_once(game, operation, context, store) do
    restore =
      if match?({:email_request, _, _, _}, operation),
        do: {:email_request_id, context.id},
        else: operation

    game = CommitExecutor.restore(game, restore, store)

    case TijaraTides.UseCases.LotAllocation.run(game, store, &execute(&1, operation, context)) do
      {:ok, changed, result} ->
        CommitExecutor.commit(game, changed, result, nil, store, & &1, Map.get(context, :wall_ms))

      {:replay, result} ->
        CommitExecutor.outcome(game, result, false)

      {:error, _} = error ->
        error
    end
  end

  defp execute(game, {:seed, hash}, _), do: Account.seed_invite(game, hash)

  defp execute(game, {:redeem, code, session}, context),
    do: Account.redeem(game, code, session, context)

  defp execute(game, {:sign_out, session}, _), do: {:ok, Account.sign_out(game, session), %{}}

  defp execute(game, {:advance, elapsed}, context),
    do: {:ok, Game.advance(game, elapsed, context.catalogue), %{}}

  defp execute(game, {:email_request, account, purpose, address}, context) do
    if ReadState.get(game, "email_requests", context.id) do
      {:replay, %{"requested" => true}}
    else
      EmailIdentity.request(game, account, purpose, address, context)
    end
  end

  defp execute(game, {:email_redeem, code, device, session}, context),
    do: EmailIdentity.redeem(game, code, device, account(game, session, context.wall_ms), context)

  defp execute(game, {action, id}, context) when action in [:email_failed, :email_delivered] do
    case ReadState.get(game, "email_requests", id) do
      nil ->
        {:replay, %{}}

      row ->
        next =
          if action == :email_failed,
            do: EmailIdentity.delivery_failed(game, row, context.wall_ms),
            else: EmailIdentity.delivered(game, row)

        {:ok, next, %{}}
    end
  end

  defp account(game, session, wall_ms) do
    case Account.authenticate(game, session, wall_ms) do
      {:ok, account} -> account
      _ -> nil
    end
  end
end
