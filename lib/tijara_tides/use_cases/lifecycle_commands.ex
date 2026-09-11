defmodule TijaraTides.UseCases.LifecycleCommands do
  @moduledoc "Identity and simulation workflows with explicit credentials, time and atomic persistence."
  alias TijaraTides.Domain.{Account, EmailIdentity, Game, ReadState}
  alias TijaraTides.UseCases.CommitExecutor

  def run(game, operation, context, store) do
    case execute(game, operation, context) do
      {:ok, changed, result} -> CommitExecutor.commit(game, changed, result, nil, store)
      {:replay, result} -> CommitExecutor.outcome(game, result, false)
      {:error, _} = error -> error
    end
  end

  defp execute(game, {:seed, hash}, _), do: Account.seed_invite(game, hash)

  defp execute(game, {:redeem, code, session}, context),
    do: Account.redeem(game, code, session, context)

  defp execute(game, {:sign_out, session}, _), do: {:ok, Account.sign_out(game, session), %{}}

  defp execute(game, {:advance, elapsed}, context),
    do: {:ok, Game.advance(game, elapsed, context.catalogue), %{}}

  defp execute(game, {:email_request, session, purpose, address}, context) do
    if ReadState.get(game, "email_requests", context.id) do
      {:replay, %{"requested" => true}}
    else
      EmailIdentity.request(
        game,
        account(game, session, context.wall_ms),
        purpose,
        address,
        context
      )
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
