defmodule TijaraTides.UseCases.OperatorCommands do
  @moduledoc "Trusted operator operations, separate from authenticated player commands."
  alias TijaraTides.Domain.{Account, AccountWorld, EmailIdentity, ReadState}
  alias TijaraTides.UseCases.CommitExecutor

  # Player account IDs are server-generated UUIDs. This reserved receipt owner
  # gives operator request IDs a world-wide namespace inaccessible to players.
  @receipt_owner "operator:grant_invitations"

  def validate(selector, count, request_id) do
    cond do
      not valid_identifier?(request_id) ->
        {:error, :invalid_request_id}

      not is_integer(count) or count < 1 or count > Account.invitation_limit() ->
        {:error, :invalid_invitation_count}

      true ->
        normalize_selector(selector)
    end
  end

  def grant_invitations(game, selector, count, request_id, context, {store, storage} = port) do
    with {:ok, selector} <- validate(selector, count, request_id) do
      fingerprint =
        :crypto.hash(:sha256, :erlang.term_to_binary({:grant_invitations, selector, count}))
        |> Base.encode16(case: :lower)

      CommitExecutor.replan(game, port, fn fresh ->
        # Check replay before target resolution or capacity: the original result
        # remains valid after the allowance is spent or an email is changed.
        case store.receipt(storage, @receipt_owner, request_id, fingerprint) do
          {:replay, result} ->
            CommitExecutor.outcome(fresh, result, false)

          {:error, reason} ->
            {:error, reason}

          :new ->
            with {:ok, account_id} <- resolve(fresh, selector),
                 {:ok, changed, result} <-
                   AccountWorld.grant_invitations(fresh, account_id, count) do
              result = Map.put(result, "request_id", request_id)
              receipt = {@receipt_owner, request_id, fingerprint, result}
              CommitExecutor.commit(fresh, changed, result, receipt, port, & &1, context.wall_ms)
            end
        end
      end)
    end
  end

  defp normalize_selector({:account, id}) do
    if valid_identifier?(id), do: {:ok, {:account, id}}, else: {:error, :invalid_account_id}
  end

  defp normalize_selector({:email, address}) do
    with {:ok, address} <- EmailIdentity.normalize(address), do: {:ok, {:email, address}}
  end

  defp normalize_selector(_), do: {:error, :invalid_account_selector}

  defp valid_identifier?(value),
    do:
      is_binary(value) and byte_size(value) in 1..128 and String.valid?(value) and
        not Regex.match?(~r/[\p{Cc}\p{Cf}\s]/u, value)

  defp resolve(game, {:account, id}) do
    if ReadState.get(game, "accounts", id), do: {:ok, id}, else: {:error, :account_not_found}
  end

  defp resolve(game, {:email, address}) do
    matches =
      ReadState.entities(game, "accounts")
      |> Map.values()
      |> Enum.filter(&(&1["email"] == address))

    case matches do
      [account] -> {:ok, account["id"]}
      [] -> {:error, :account_not_found}
      _ -> {:error, :ambiguous_account}
    end
  end
end
