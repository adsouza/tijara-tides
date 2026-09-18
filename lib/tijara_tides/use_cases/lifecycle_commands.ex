defmodule TijaraTides.UseCases.LifecycleCommands do
  alias TijaraTides.Domain.AccountWorld

  @moduledoc "Identity and simulation workflows with explicit credentials, time and atomic persistence."
  alias TijaraTides.Domain.{EmailIdentity, Game, ReadState}
  alias TijaraTides.UseCases.{Authentication, CommitExecutor}

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

    planned =
      TijaraTides.UseCases.Observation.measure(:planning, fn ->
        TijaraTides.UseCases.LotAllocation.run(game, store, &execute(&1, operation, context))
      end)

    case planned do
      {:ok, changed, result} ->
        CommitExecutor.commit(game, changed, result, nil, store, & &1, Map.get(context, :wall_ms))

      {:replay, result} ->
        CommitExecutor.outcome(game, result, false)

      {:error, _} = error ->
        error
    end
  end

  defp execute(game, {:seed, hash}, _), do: AccountWorld.seed_invite(game, hash)

  defp execute(game, {:redeem, code, session}, context),
    do: AccountWorld.redeem(game, code, session, context)

  defp execute(game, {:sign_out, session}, _),
    do: {:ok, AccountWorld.sign_out(game, session), %{}}

  defp execute(game, {:advance, elapsed}, context) do
    wall = Map.get(context, :wall_ms)

    scale =
      if is_integer(wall),
        do: TijaraTides.Domain.ParticipationWorld.index(game, wall, context.catalogue),
        else: 10_000

    changed =
      game
      |> Map.put(:participation_bps, scale)
      |> Game.advance(elapsed, context.catalogue, &TijaraTides.UseCases.Observation.measure/2)

    {:ok, TijaraTides.Domain.ParticipationWorld.observe(game, changed, wall, context.catalogue),
     %{}}
  end

  defp execute(game, {:email_request, session, purpose, address}, context) do
    if ReadState.get(game, "email_requests", context.id) do
      {:replay, %{"requested" => true}}
    else
      account = Authentication.optional(game, session, context.wall_ms)
      # Rate-limit attribution and identity use the same authentication result and clock.
      requester =
        if account,
          do: :crypto.hash(:sha256, account["id"]) |> Base.encode16(case: :lower),
          else: context.requester

      EmailIdentity.request(game, account, purpose, address, %{context | requester: requester})
    end
  end

  defp execute(game, {:email_redeem, code, device, session}, context),
    do:
      EmailIdentity.redeem(
        game,
        code,
        device,
        Authentication.optional(game, session, context.wall_ms),
        context
      )

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
end
