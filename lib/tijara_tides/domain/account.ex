defmodule TijaraTides.Domain.Account do
  @moduledoc "Account lifecycle rules with explicit time and admission facts."
  alias __MODULE__.{BankruptcyEvent, EmailIdentity}

  @fields ~w(id company_id inviter bankruptcies suspended_ms email invite_quota created_ms locale)a
  defstruct @fields ++ [sessions: [], invitations: [], email_requests: [], bankruptcy_events: []]
  @history_ms 112 * 86_400_000
  def history_ms, do: @history_ms

  def suspended?(%__MODULE__{suspended_ms: value}), do: value != nil

  def new(id, inviter, seed?, now) do
    %__MODULE__{
      id: id,
      company_id: nil,
      inviter: inviter,
      bankruptcies: 0,
      suspended_ms: nil,
      email: nil,
      locale: "en",
      invite_quota: if(seed?, do: 3, else: 0),
      created_ms: now
    }
  end

  def consume_invitation(%__MODULE__{} = account) do
    unless not suspended?(account) and is_integer(account.invite_quota) and
             account.invite_quota > 0,
           do: raise(ArgumentError, "Account has no available invitation quota")

    %{account | invite_quota: account.invite_quota - 1}
  end

  def issue_invitation(%__MODULE__{} = account, outstanding) do
    if not suspended?(account) and account.invite_quota > 0 and outstanding < 3,
      do: {:ok, consume_invitation(account)},
      else: {:error, :no_invitation_quota}
  end

  def restore_invitation(%__MODULE__{} = account),
    do: %{account | invite_quota: account.invite_quota + 1}

  def counted(%__MODULE__{} = account, now),
    do: Enum.count(account.bankruptcy_events, &(&1.created_ms + @history_ms > now))

  def restart_at(%__MODULE__{} = account, cooldown_ms),
    do:
      account.bankruptcy_events
      |> Enum.map(&min(&1.restart_ms, &1.created_ms + cooldown_ms))
      |> Enum.max(fn -> 0 end)

  def attach_company(%__MODULE__{} = account, company_id, eligible?, now, cooldown_ms) do
    unless eligible? and account.company_id == nil and not suspended?(account) and
             restart_at(account, cooldown_ms) <= now,
           do: raise(ArgumentError, "Account cannot attach this active company")

    %{account | company_id: company_id}
  end

  def verify_email(%__MODULE__{} = account, email, collision?, session_available?) do
    unless match?({:ok, ^email}, EmailIdentity.normalize(email)) and not collision? and
             session_available?,
           do:
             raise(
               ArgumentError,
               "Verified identity or device session belongs to another account"
             )

    %{account | email: email}
  end

  def record_bankruptcy(
        %__MODULE__{} = account,
        %BankruptcyEvent{} = event,
        company_closed?,
        event_exists?
      ) do
    unless account.company_id == event.company_id and event.account_id == account.id and
             company_closed? and not event_exists?,
           do:
             raise(
               ArgumentError,
               "Bankruptcy must close the account's active company exactly once"
             )

    next = %{
      account
      | company_id: nil,
        bankruptcies: account.bankruptcies + 1,
        bankruptcy_events: account.bankruptcy_events ++ [event]
    }

    if counted(next, event.created_ms) >= 5,
      do: %{next | suspended_ms: event.created_ms},
      else: next
  end

  def reinstate(%__MODULE__{} = account, funded_sponsor_pledge?) do
    unless funded_sponsor_pledge?,
      do: raise(ArgumentError, "Reinstatement requires a funded pledge from the original sponsor")

    %{account | suspended_ms: nil}
  end

  def set_locale(%__MODULE__{} = account, locale) when locale in ["en", "ar"],
    do: {:ok, %{account | locale: locale}}

  def set_locale(%__MODULE__{}, _), do: {:error, :invalid_locale}
end
