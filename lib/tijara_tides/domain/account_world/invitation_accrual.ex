defmodule TijaraTides.Domain.AccountWorld.InvitationAccrual do
  @moduledoc "Award invitations and persist bounded account progress in the same world transaction."
  alias TijaraTides.Domain.{Account, ChangeSet, Notices, Participation, State}
  alias TijaraTides.Domain.Account.{InvitationProgress, Rows}

  @doc "Read the next earning opportunity and unused-invitation expiry without awarding quota."
  def forecast(state, account) do
    company = State.get(state, "companies", account["company_id"])
    row = State.get(state, "invitation_progress", account["id"])
    issued = issued(state, account["id"])

    refund_ms =
      issued
      |> Enum.map(&max(0, &1["expires_ms"] - state.clock_ms))
      |> Enum.min(fn -> nil end)

    status =
      cond do
        account["suspended_ms"] != nil ->
          "suspended"

        company == nil or company["bankruptcy_ms"] != nil ->
          "no_company"

        not healthy?(state, account) ->
          "financial_trouble"

        account["invite_quota"] + length(issued) >= InvitationProgress.limit() ->
          "capacity"

        row == nil or row["company_id"] != account["company_id"] or
            row["active_until_ms"] < state.clock_ms ->
          "inactive"

        true ->
          "earning"
      end

    remaining_ms =
      if status == "earning" do
        elapsed = max(0, min(state.clock_ms, row["active_until_ms"]) - row["checked_ms"])
        max(0, InvitationProgress.period_ms() - row["progress_ms"] - elapsed)
      else
        InvitationProgress.period_ms()
      end

    %{"status" => status, "remaining_ms" => remaining_ms, "refund_ms" => refund_ms}
  end

  defp issued(state, id),
    do: Enum.filter(State.owned(state, "invitations", "inviter", id), &(&1["status"] == "issued"))

  def observe(before, changed, catalogue, scope \\ :changed) do
    settings = Participation.settings(catalogue)

    active =
      Map.get(changed, :journal, [])
      |> Enum.drop(length(Map.get(before, :journal, [])))
      |> Enum.filter(&Participation.qualifies?(&1, settings))
      |> MapSet.new(& &1.company)

    ids =
      if scope == :all do
        Map.keys(State.entities(changed, "accounts"))
      else
        companies = ChangeSet.affected_companies(before, changed) ++ MapSet.to_list(active)

        accounts =
          for {{"accounts", id}, _} <- ChangeSet.since(before, changed), do: id

        (accounts ++
           for(
             company <- companies,
             state <- [before, changed],
             row = State.get(state, "companies", company),
             row != nil,
             do: row["account_id"]
           ))
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq()
      end

    Enum.reduce(ids, changed, fn id, state -> advance_account(before, state, id, active) end)
  end

  defp advance_account(before, state, id, active) do
    account = State.get(state, "accounts", id)
    company = account["company_id"]
    row = State.get(state, "invitation_progress", id)
    active? = MapSet.member?(active, company) and healthy?(state, account)

    # Existing companies begin earning with their first qualifying action after
    # upgrade. Wall-clock participation history cannot backdate world-clock credit.
    if row || active? do
      row = row || InvitationProgress.new(id, company, state.clock_ms)
      previous = State.get(before, "accounts", id)
      eligible? = healthy?(before, previous) and healthy?(state, account)

      outstanding = length(issued(state, id))

      capacity = max(0, InvitationProgress.limit() - account["invite_quota"] - outstanding)

      {row, earned} =
        InvitationProgress.advance(row, company, state.clock_ms, eligible?, active?, capacity)

      state = State.put(state, "invitation_progress", id, row)

      if earned > 0 do
        account = account |> Rows.decode() |> Account.earn_invitations(earned)

        state
        |> State.put("accounts", id, Rows.encode(account))
        |> Notices.notice(
          id,
          "invitation-earned:" <> id <> ":" <> to_string(state.clock_ms),
          {"invitation.earned", %{}}
        )
      else
        state
      end
    else
      state
    end
  end

  defp healthy?(_state, nil), do: false

  defp healthy?(state, account) do
    company = State.get(state, "companies", account["company_id"])

    account["suspended_ms"] == nil and company != nil and
      company["account_id"] == account["id"] and company["bankruptcy_ms"] == nil and
      company["unpaid"] == 0 and company["arrears_since"] == nil and
      Enum.all?(
        State.owned(state, "loans", "open_company_id", company["id"]),
        &(&1["principal_due"] == 0 and &1["interest_due"] == 0 and &1["overdue_ms"] == nil)
      )
  end
end
