defmodule TijaraTides.Domain.Account do
  @moduledoc "Accounts, invitation entitlements, device-session authentication, and company formation."
  import TijaraTides.Domain.State
  import TijaraTides.Domain.Notices, only: [notice: 4]
  @invite_ms 3 * 86_400_000

  @fields ~w(id company_id inviter bankruptcies suspended_ms email invite_quota created_ms)a
  defstruct @fields ++ [sessions: [], invitations: [], email_requests: [], bankruptcy_events: []]
  @history_ms 112 * 86_400_000
  def history_ms, do: @history_ms

  @doc "Reconstitute identity history supplied by the persistence read-through port."
  def restore_history(state, kind, id, row)
      when kind in ["sessions", "invitations", "email_requests"],
      do: cache(state, kind, id, row)

  def compact_history(state, wall_ms) do
    if wall_ms < Map.get(state, :identity_compacted_at, -60_000) + 60_000 do
      state
    else
      state =
        Enum.reduce(entities(state, "sessions"), state, fn {id, row}, acc ->
          if row["expires_at"] <= wall_ms, do: evict(acc, "sessions", id), else: acc
        end)

      state =
        Enum.reduce(entities(state, "invitations"), state, fn {id, row}, acc ->
          if row["status"] != "issued", do: evict(acc, "invitations", id), else: acc
        end)

      recent_deliveries =
        entities(state, "email_requests")
        |> Map.values()
        |> Enum.filter(&(&1["purpose"] in ["link", "invite"]))
        |> Enum.group_by(& &1["account_id"])
        |> Enum.flat_map(fn {_, rows} ->
          Enum.sort_by(rows, &{-&1["created_ms"], &1["id"]}) |> Enum.take(10)
        end)
        |> MapSet.new(& &1["id"])

      state =
        Enum.reduce(entities(state, "email_requests"), state, fn {id, row}, acc ->
          live_delivery =
            row["delivery"] == "pending" and row["used_session"] == nil and
              row["expires_ms"] >
                if(row["purpose"] == "invite", do: state.clock_ms, else: wall_ms)

          if row["created_ms"] > wall_ms - 3_600_000 or live_delivery or
               MapSet.member?(recent_deliveries, id),
             do: acc,
             else: evict(acc, "email_requests", id)
        end)

      Map.put(state, :identity_compacted_at, wall_ms)
    end
  end

  def from_row(row),
    do: struct!(__MODULE__, Map.new(@fields, &{&1, row[Atom.to_string(&1)]}))

  def to_row(%__MODULE__{} = account),
    do: Map.new(@fields, &{Atom.to_string(&1), Map.fetch!(account, &1)})

  def from_world(state, id) do
    account = from_row(get(state, "accounts", id))

    owned = fn kind, field ->
      TijaraTides.Domain.State.owned(state, kind, field, id)
    end

    %{
      account
      | sessions: owned.("sessions", "account_id"),
        invitations: owned.("invitations", "inviter"),
        email_requests: owned.("email_requests", "account_id"),
        bankruptcy_events: history(state, to_row(account))
    }
  end

  defp store(state, %__MODULE__{} = account),
    do: put(state, "accounts", account.id, to_row(account))

  def suspended?(%__MODULE__{suspended_ms: value}), do: value != nil
  def suspended?(account), do: not is_nil(account) and account["suspended_ms"] != nil

  def consume_invitation(%__MODULE__{} = account) do
    unless not suspended?(account) and is_integer(account.invite_quota) and
             account.invite_quota > 0,
           do: raise(ArgumentError, "Account has no available invitation quota")

    %{account | invite_quota: account.invite_quota - 1}
  end

  def attach_company(state, account_id, company_id) do
    account = from_row(get(state, "accounts", account_id))
    company = get(state, "companies", company_id)

    unless not is_nil(company) and company["account_id"] == account_id and
             company["bankruptcy_ms"] == nil and
             account.company_id == nil and not suspended?(account) and
             restart_at(state, to_row(account)) <= state.clock_ms,
           do: raise(ArgumentError, "Account cannot attach this active company")

    store(state, %{account | company_id: company_id})
  end

  def verify_email(state, account_id, email, session, expires_at) do
    account = from_row(get(state, "accounts", account_id))

    collision =
      Enum.any?(owned(state, "accounts", "email", email), &(&1["id"] != account_id))

    existing_session = get(state, "sessions", session)

    unless match?({:ok, ^email}, __MODULE__.EmailIdentity.normalize(email)) and not collision and
             (existing_session == nil or existing_session["account_id"] == account_id),
           do:
             raise(
               ArgumentError,
               "Verified identity or device session belongs to another account"
             )

    state
    |> store(%{account | email: email})
    |> put("sessions", session, %{"account_id" => account_id, "expires_at" => expires_at})
  end

  def history(state, account) do
    owned(state, "bankruptcy_events", "account_id", account["id"])
  end

  def counted(state, account),
    do: Enum.count(history(state, account), &(&1["created_ms"] + @history_ms > state.clock_ms))

  def restart_at(state, account),
    do: history(state, account) |> Enum.map(& &1["restart_ms"]) |> Enum.max(fn -> 0 end)

  def record_bankruptcy(state, account_id, company_id, reason, cooldown) do
    account = from_row(get(state, "accounts", account_id))
    company = get(state, "companies", company_id)

    unless account.company_id == company_id and company["account_id"] == account_id and
             company["bankruptcy_ms"] != nil and
             get(state, "bankruptcy_events", company_id) == nil,
           do:
             raise(
               ArgumentError,
               "Bankruptcy must close the account's active company exactly once"
             )

    account = %{account | company_id: nil, bankruptcies: account.bankruptcies + 1}

    state =
      state
      |> store(account)
      |> put("bankruptcy_events", company_id, %{
        "id" => company_id,
        "company_id" => company_id,
        "account_id" => account_id,
        "created_ms" => state.clock_ms,
        "restart_ms" => state.clock_ms + cooldown,
        "reason" => reason
      })

    if counted(state, to_row(account)) >= 5 do
      state
      |> store(%{account | suspended_ms: state.clock_ms})
      |> notice(
        account_id,
        "suspension",
        "Account suspended after five recent bankruptcies. Your original sponsor must pledge at least $50,000 to reinstate you."
      )
      |> notice(
        account.inviter,
        "suspension:" <> account_id,
        "An invitee is suspended and needs your cash-backed guarantee. Review sponsor guarantees in the account menu."
      )
    else
      state
    end
  end

  def reinstate(state, account_id, guarantee_id) do
    account = from_row(get(state, "accounts", account_id))
    guarantee = get(state, "guarantees", guarantee_id)

    unless not is_nil(guarantee) and guarantee["beneficiary_id"] == account_id and
             guarantee["sponsor_id"] == account.inviter and guarantee["status"] == "pledged" and
             guarantee["amount"] >= 5_000_000,
           do:
             raise(
               ArgumentError,
               "Reinstatement requires a funded pledge from the original sponsor"
             )

    store(state, %{account | suspended_ms: nil})
  end

  def sign_out(state, session_hash), do: delete(state, "sessions", session_hash)

  def authenticate(state, session_hash, wall_ms) do
    case get(state, "sessions", session_hash) do
      %{"account_id" => id, "expires_at" => expiry} when expiry > wall_ms ->
        case get(state, "accounts", id) do
          nil -> {:error, :invalid_session}
          account -> {:ok, account}
        end

      _ ->
        {:error, :invalid_session}
    end
  end

  def seed_invite(state, hash) do
    if get(state, "invitations", hash),
      do: {:error, :already_exists},
      else:
        {:ok,
         put(state, "invitations", hash, %{
           "inviter" => nil,
           "expires_ms" => state.clock_ms + @invite_ms,
           "status" => "issued",
           "seed" => true
         }), %{"created" => true}}
  end

  def redeem(state, hash, session_hash, context) do
    email_invite =
      Enum.any?(entities(state, "email_requests"), fn {_, r} ->
        r["purpose"] == "invite" and r["token_hash"] == hash
      end)

    if email_invite and not Map.get(context, :email_verification, false),
      do: {:error, :invalid_invitation},
      else: redeem_invitation(state, hash, session_hash, context)
  end

  defp redeem_invitation(state, hash, session_hash, context) do
    case get(state, "invitations", hash) do
      %{"status" => "redeemed", "invitee" => account_id} ->
        case authenticate(state, session_hash, context.wall_ms) do
          {:ok, %{"id" => ^account_id}} -> {:replay, %{"account_id" => account_id}}
          _ -> {:error, :invalid_invitation}
        end

      _ ->
        # A device credential can bootstrap only one account. Never overwrite a
        # session when concurrent forms submit two different invitations.
        if get(state, "sessions", session_hash),
          do: {:error, :invalid_invitation},
          else: redeem_new(state, hash, session_hash, context)
    end
  end

  defp redeem_new(state, hash, session_hash, context) do
    with %{"status" => "issued", "expires_ms" => expiry} = invite <-
           get(state, "invitations", hash),
         true <- state.clock_ms < expiry do
      id = context.id

      account = %{
        "id" => id,
        "company_id" => nil,
        "inviter" => invite["inviter"],
        "bankruptcies" => 0,
        "suspended_ms" => nil,
        "email" => nil,
        "invite_quota" => if(invite["seed"], do: 3, else: 0),
        "created_ms" => state.clock_ms
      }

      state =
        state
        |> put("accounts", id, account)
        |> put("sessions", session_hash, %{
          "account_id" => id,
          "expires_at" => context.wall_ms + 365 * 86_400_000
        })
        |> put("invitations", hash, Map.merge(invite, %{"status" => "redeemed", "invitee" => id}))

      state =
        notice(
          state,
          invite["inviter"],
          "accepted:" <> id,
          "Your invitation was accepted. Company formation is pending."
        )

      {:ok, state, %{"account_id" => id}}
    else
      _ -> {:error, :invalid_invitation}
    end
  end

  def issue_invite(state, account, context) do
    account = get(state, "accounts", account["id"])

    outstanding =
      Enum.count(entities(state, "invitations"), fn {_, i} ->
        i["inviter"] == account["id"] and i["status"] == "issued"
      end)

    if not __MODULE__.suspended?(account) and account["invite_quota"] > 0 and
         outstanding < 3 do
      state =
        state
        |> store(from_row(account) |> consume_invitation())
        |> put("invitations", context.invite_hash, %{
          "inviter" => account["id"],
          "expires_ms" => state.clock_ms + @invite_ms,
          "status" => "issued",
          "seed" => false
        })

      {:ok, state,
       %{"invitation" => context.invite_hash, "expires_ms" => state.clock_ms + @invite_ms}}
    else
      {:error, :no_invitation_quota}
    end
  end

  def expire_invitations(state) do
    now = state.clock_ms

    Enum.reduce(entities(state, "invitations"), state, fn {id, invite}, state ->
      if invite["status"] == "issued" and invite["expires_ms"] <= now do
        state = put(state, "invitations", id, %{invite | "status" => "expired"})

        case get(state, "accounts", invite["inviter"]) do
          nil ->
            state

          account ->
            store(state, %{from_row(account) | invite_quota: account["invite_quota"] + 1})
        end
      else
        state
      end
    end)
  end
end
