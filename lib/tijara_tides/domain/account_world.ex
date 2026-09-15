defmodule TijaraTides.Domain.AccountWorld do
  @moduledoc "Accounts, invitation entitlements, device-session authentication, and company formation."
  import TijaraTides.Domain.State
  import TijaraTides.Domain.Notices, only: [notice: 4]
  @invite_ms 3 * 86_400_000

  alias TijaraTides.Domain.Account
  alias TijaraTides.Domain.Account.{Rows, BankruptcyRows, BankruptcyEvent}
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

  def fetch(state, id) do
    # An absent account reads as an empty one; the codec no longer decodes a nil row.
    account =
      case get(state, "accounts", id) do
        nil -> %Account{id: id, locale: "en"}
        row -> Rows.decode(row)
      end

    owned = fn kind, field ->
      TijaraTides.Domain.State.owned(state, kind, field, id)
    end

    %{
      account
      | sessions: owned.("sessions", "account_id"),
        invitations: owned.("invitations", "inviter"),
        email_requests: owned.("email_requests", "account_id"),
        bankruptcy_events:
          Enum.map(history(state, Rows.encode(account)), &BankruptcyRows.decode/1)
    }
  end

  defp store(state, %Account{} = account),
    do: put(state, "accounts", account.id, Rows.encode(account))

  def suspended?(%Account{} = account), do: Account.suspended?(account)
  def suspended?(account), do: not is_nil(account) and account["suspended_ms"] != nil

  def attach_company(state, account_id, company_id) do
    account = fetch(state, account_id)
    company = get(state, "companies", company_id)

    eligible =
      company != nil and company["account_id"] == account_id and company["bankruptcy_ms"] == nil

    store(
      state,
      Account.attach_company(
        account,
        company_id,
        eligible,
        state.clock_ms,
        TijaraTides.Domain.CompanyFinance.terms().cooldown_ms
      )
    )
  end

  def verify_email(state, account_id, email, session, expires_at) do
    account = Rows.decode(get(state, "accounts", account_id))

    collision =
      Enum.any?(owned(state, "accounts", "email", email), &(&1["id"] != account_id))

    existing_session = get(state, "sessions", session)

    account =
      Account.verify_email(
        account,
        email,
        collision,
        existing_session == nil or existing_session["account_id"] == account_id
      )

    state
    |> store(account)
    |> put("sessions", session, %{"account_id" => account_id, "expires_at" => expires_at})
  end

  def history(state, account) do
    owned(state, "bankruptcy_events", "account_id", account["id"])
  end

  def counted(state, account), do: Account.counted(fetch(state, account["id"]), state.clock_ms)

  def restart_at(state, account),
    do:
      Account.restart_at(
        fetch(state, account["id"]),
        TijaraTides.Domain.CompanyFinance.terms().cooldown_ms
      )

  @doc """
  Record the closure. `escrow` names the guarantee this failure consumed and the debt it
  must cover, as `{guarantee_id, cents}`; the sponsor forfeits it from its own books later.
  """
  def record_bankruptcy(state, account_id, company_id, reason, cooldown, escrow \\ nil) do
    account = fetch(state, account_id)
    company = get(state, "companies", company_id)

    event = %BankruptcyEvent{
      id: company_id,
      company_id: company_id,
      account_id: account_id,
      created_ms: state.clock_ms,
      restart_ms: state.clock_ms + cooldown,
      reason: reason,
      guarantee_id: if(escrow, do: elem(escrow, 0)),
      guaranteed_debt: if(escrow, do: elem(escrow, 1), else: 0)
    }

    account =
      Account.record_bankruptcy(
        account,
        event,
        company != nil and company["account_id"] == account_id and company["bankruptcy_ms"] != nil,
        get(state, "bankruptcy_events", company_id) != nil
      )

    state =
      state
      |> store(account)
      |> put("bankruptcy_events", company_id, BankruptcyRows.encode(event))

    if Account.counted(account, state.clock_ms) >= 5 do
      state
      |> notice(
        account_id,
        "suspension",
        {"account.suspended", %{}}
      )
      |> notice(
        account.inviter,
        "suspension:" <> account_id,
        {"account.invitee_suspended", %{}}
      )
    else
      state
    end
  end

  def reinstate(state, account_id, guarantee_id) do
    account = Rows.decode(get(state, "accounts", account_id))
    guarantee = get(state, "guarantees", guarantee_id)

    funded =
      not is_nil(guarantee) and guarantee["beneficiary_id"] == account_id and
        guarantee["sponsor_id"] == account.inviter and guarantee["status"] == "pledged" and
        guarantee["amount"] >= 5_000_000

    store(state, Account.reinstate(account, funded))
  end

  def set_locale(state, account, locale) when locale in ["en", "ar"] do
    {:ok, current} = Account.set_locale(fetch(state, account["id"]), locale)
    {:ok, store(state, current), %{}}
  end

  def set_locale(_state, _account, _locale), do: {:error, :invalid_locale}

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

      account = Account.new(id, invite["inviter"], invite["seed"], state.clock_ms)

      state =
        state
        |> store(account)
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
          {"invitation.accepted", %{}}
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

    case Account.issue_invitation(Rows.decode(account), outstanding) do
      {:ok, updated} ->
        state =
          state
          |> store(updated)
          |> put("invitations", context.invite_hash, %{
            "inviter" => account["id"],
            "expires_ms" => state.clock_ms + @invite_ms,
            "status" => "issued",
            "seed" => false
          })

        {:ok, state,
         %{"invitation" => context.invite_hash, "expires_ms" => state.clock_ms + @invite_ms}}

      error ->
        error
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
            store(state, Account.restore_invitation(Rows.decode(account)))
        end
      else
        state
      end
    end)
  end
end
