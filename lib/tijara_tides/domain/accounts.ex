defmodule TijaraTides.Domain.Accounts do
  @moduledoc "Accounts, invitation entitlements, device-session authentication, and company formation."
  import TijaraTides.Domain.State
  import TijaraTides.Domain.Notices, only: [notice: 4]
  alias TijaraTides.Domain.Finance
  @invite_ms 3 * 86_400_000

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

  def create_company(state, account, name, context) do
    name = if is_binary(name), do: String.trim(name), else: ""

    cond do
      TijaraTides.Domain.Guarantees.suspended?(get(state, "accounts", account["id"])) ->
        {:error, :account_suspended}

      account["company_id"] != nil ->
        {:error, :company_exists}

      Finance.restart_at(state, account) > state.clock_ms ->
        {:error, :bankruptcy_cooldown}

      name == "" or String.length(name) > 60 ->
        {:error, :invalid_name}

      Enum.any?(entities(state, "companies"), fn {_, c} ->
        String.downcase(c["name"]) == String.downcase(name)
      end) ->
        {:error, :name_taken}

      true ->
        id = context.id

        company = %{
          "id" => id,
          "account_id" => account["id"],
          "name" => name,
          "cash" => 0,
          "reserved" => 0,
          "profit" => 0,
          "unpaid" => 0,
          "created_ms" => state.clock_ms,
          "last_invite_year" => 0,
          "unpaid_since" => nil,
          "arrears_since" => nil,
          "bankruptcy_ms" => nil
        }

        state =
          state
          |> put("companies", id, company)
          |> put("accounts", account["id"], %{account | "company_id" => id})

        state =
          notice(state, account["inviter"], "company:" <> id, "Your invitee now runs #{name}.")

        {:ok, state, %{"company_id" => id}}
    end
  end

  def issue_invite(state, account, context) do
    outstanding =
      Enum.count(entities(state, "invitations"), fn {_, i} ->
        i["inviter"] == account["id"] and i["status"] == "issued"
      end)

    if not TijaraTides.Domain.Guarantees.suspended?(account) and account["invite_quota"] > 0 and
         outstanding < 3 do
      state =
        state
        |> put("accounts", account["id"], %{
          account
          | "invite_quota" => account["invite_quota"] - 1
        })
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
            put(state, "accounts", account["id"], %{
              account
              | "invite_quota" => account["invite_quota"] + 1
            })
        end
      else
        state
      end
    end)
  end
end
