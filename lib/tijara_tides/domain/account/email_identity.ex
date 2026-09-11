defmodule TijaraTides.Domain.Account.EmailIdentity do
  @moduledoc "Verified email identities and single-use email credentials. No delivery or cryptography."
  import TijaraTides.Domain.State
  alias TijaraTides.Domain.Account

  def delivered(state, row) do
    current = get(state, "email_requests", row["id"])
    put(state, "email_requests", current["id"], %{current | "delivery" => "sent"})
  end

  def delivery_failed(state, row, wall_ms) do
    row = get(state, "email_requests", row["id"])
    attempts = row["attempts"] + 1

    put(state, "email_requests", row["id"], %{
      row
      | "attempts" => attempts,
        "retry_ms" => wall_ms + min(3_600_000, 30_000 * Integer.pow(2, min(attempts, 7))),
        "delivery" => if(attempts >= 8, do: "failed", else: "pending")
    })
  end

  def normalize(value) when is_binary(value) do
    email = if String.valid?(value), do: value |> String.trim() |> String.downcase(), else: ""

    if byte_size(email) <= 254 and Regex.match?(~r/^[^\s@<>]+@[^\s@<>]+\.[^\s@<>]+$/, email),
      do: {:ok, email},
      else: {:error, :email_invalid}
  end

  def normalize(_), do: {:error, :email_invalid}

  def request(state, account, purpose, address, context) do
    with {:ok, email} <- normalize(address) do
      recent =
        entities(state, "email_requests")
        |> Map.values()
        |> Enum.filter(&(&1["created_ms"] > context.wall_ms - 3_600_000))

      owner =
        Enum.find_value(entities(state, "accounts"), fn {_, a} ->
          if a["email"] == email, do: a
        end)

      cond do
        purpose not in ["login", "link", "invite"] ->
          {:error, :email_invalid}

        purpose != "login" and is_nil(account) ->
          {:error, :invalid_session}

        purpose == "invite" and Account.suspended?(account) ->
          {:error, :account_suspended}

        Enum.count(recent, &(&1["requester"] == context.requester)) >= 10 or
            Enum.count(recent, &(&1["email"] == email)) >= 3 ->
          {:error, :email_rate_limited}

        (purpose in ["link", "invite"] and owner) &&
            (purpose == "invite" or owner["id"] != account["id"]) ->
          {:error, :email_unavailable}

        true ->
          invited =
            if purpose == "invite",
              do: Account.issue_invite(state, account, %{invite_hash: context.hash}),
              else: {:ok, state, %{}}

          with {:ok, state, _} <- invited do
            target = if purpose == "login", do: owner, else: account

            row = %{
              "id" => context.id,
              "token_hash" => context.hash,
              "email" => email,
              "purpose" => purpose,
              "account_id" => target && target["id"],
              "requester" => context.requester,
              "created_ms" => context.wall_ms,
              "expires_ms" =>
                if(purpose == "invite",
                  do: state.clock_ms + 3 * 86_400_000,
                  else: context.wall_ms + 900_000
                ),
              "used_session" => nil,
              "attempts" => 0,
              "retry_ms" => 0,
              "delivery" =>
                if(purpose == "login" and is_nil(owner), do: "ignored", else: "pending")
            }

            {:ok, put(state, "email_requests", context.id, row), %{"requested" => true}}
          end
      end
    end
  end

  def redeem(state, hash, session, signed_in, context) do
    row =
      Enum.find_value(entities(state, "email_requests"), fn {_, row} ->
        if row["token_hash"] == hash, do: row
      end)

    cond do
      is_nil(row) ->
        {:error, :email_link_invalid}

      row["used_session"] == session ->
        case Account.authenticate(state, session, context.wall_ms) do
          {:ok, _} -> {:ok, state, %{"verified" => true}}
          _ -> {:error, :email_link_invalid}
        end

      row["purpose"] == "login" and
          (get(state, "accounts", row["account_id"]) || %{})["email"] != row["email"] ->
        {:error, :email_link_invalid}

      row["used_session"] != nil or row["delivery"] == "ignored" ->
        {:error, :email_link_invalid}

      row["expires_ms"] <=
          if(row["purpose"] == "invite", do: state.clock_ms, else: context.wall_ms) ->
        {:error, :email_link_invalid}

      signed_in && (row["purpose"] == "invite" or signed_in["id"] != row["account_id"]) ->
        {:error, :email_wrong_account}

      row["purpose"] != "invite" and get(state, "sessions", session) != nil and
          get(state, "sessions", session)["account_id"] != row["account_id"] ->
        {:error, :email_wrong_account}

      true ->
        owner =
          Enum.find_value(entities(state, "accounts"), fn {_, a} ->
            if a["email"] == row["email"], do: a
          end)

        if owner && (row["purpose"] == "invite" or owner["id"] != row["account_id"]) do
          {:error, :email_unavailable}
        else
          result =
            if row["purpose"] == "invite",
              do:
                Account.redeem(state, hash, session, Map.put(context, :email_verification, true)),
              else: {:ok, state, %{"account_id" => row["account_id"]}}

          with {:ok, state, %{"account_id" => id}} <- result do
            state =
              state
              |> Account.verify_email(
                id,
                row["email"],
                session,
                context.wall_ms + 30 * 86_400_000
              )
              |> put("email_requests", row["id"], %{row | "used_session" => session})

            # Old, unused linking links must not replace a subsequently verified identity.
            state =
              Enum.reduce(entities(state, "email_requests"), state, fn {key, other}, acc ->
                if key != row["id"] and other["account_id"] == id and other["purpose"] == "link" and
                     other["used_session"] == nil,
                   do: put(acc, "email_requests", key, %{other | "expires_ms" => 0}),
                   else: acc
              end)

            {:ok, state, %{"verified" => true}}
          end
        end
    end
  end
end
