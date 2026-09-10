defmodule TijaraTides.UseCases.GameCommands do
  @moduledoc """
  Authenticated command workflow: validate session, check durable replay, apply
  pure rules, commit atomically, then expose the result. Transport publishes only
  committed outcomes. Persistence and invitation credentials are supplied ports.
  """
  alias TijaraTides.Domain.{Accounts, Commands}
  alias TijaraTides.UseCases.{CommandRequest, CommandResult}

  def execute(state, account, command, context),
    do: Commands.execute(state, account, command, context)

  # Compatibility for callers that still supply catalogue separately.
  def execute(state, account, command, context, catalogue),
    do: execute(state, account, command, Map.put(context, :catalogue, catalogue))

  def run(game, session_hash, %CommandRequest{} = request, context, {store, storage}, invitation) do
    with {:ok, account} <- Accounts.authenticate(game, session_hash, context.wall_ms),
         :ok <- validate_payload(request.payload) do
      %{hash: invite_hash, decorate: decorate} = invitation.(account["id"], request.id)

      case store.receipt(storage, account["id"], request.id, request.fingerprint) do
        {:replay, result} ->
          outcome(game, decorate.(result), false)

        {:error, error} ->
          {:error, error}

        :new ->
          context = Map.put(context, :invite_hash, invite_hash)

          case execute(game, account, request.payload, context) do
            {:ok, changed, result} ->
              changed =
                TijaraTides.UseCases.CommitPreparation.prepare(game, %{
                  changed
                  | revision: game.revision + 1
                })

              receipt = {account["id"], request.id, request.fingerprint, result}

              case store.commit(storage, game, changed, receipt) do
                {:ok, :ok} ->
                  outcome(
                    TijaraTides.UseCases.CommitPreparation.accepted(changed),
                    decorate.(result),
                    true
                  )

                {:error, {:replay, result}} ->
                  outcome(game, decorate.(result), false)

                {:error, error} ->
                  {:halt, error}
              end

            error ->
              error
          end
      end
    end
  end

  defp validate_payload(payload) do
    cond do
      not is_map(payload) -> {:error, :invalid_command_payload}
      map_size(payload) > 12 -> {:error, :too_many_command_fields}
      byte_size(:erlang.term_to_binary(payload)) > 4096 -> {:error, :command_payload_too_large}
      true -> :ok
    end
  end

  defp outcome(game, reply, committed?),
    do: {:ok, %CommandResult{game: game, reply: reply, committed?: committed?}}
end
