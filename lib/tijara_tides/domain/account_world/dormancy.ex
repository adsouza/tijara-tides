defmodule TijaraTides.Domain.AccountWorld.Dormancy do
  @moduledoc "Durable absence, warning outbox and separate dormant closure history."
  import TijaraTides.Domain.State
  alias TijaraTides.Domain.{Account, AccountWorld, Notices}
  alias Account.Dormancy

  def advance(state, nil, _catalogue), do: state

  def advance(state, now, catalogue),
    do: advance_accounts(state, entities(state, "accounts"), now, catalogue)

  def advance_for(state, _account, nil, _catalogue), do: state

  def advance_for(state, account, now, catalogue),
    do: advance_accounts(state, [{account["id"], account}], now, catalogue)

  defp advance_accounts(state, accounts, now, catalogue) do
    settings = Dormancy.settings(catalogue)

    Enum.reduce(Enum.sort(accounts), state, fn {_, account}, acc ->
      company = get(acc, "companies", account["company_id"])

      if company && company["bankruptcy_ms"] == nil do
        old = record(acc, company, now)
        warned = Dormancy.warn(old, now, settings)
        acc = put(acc, "company_dormancy", company["id"], Dormancy.to_row(warned))

        acc =
          if old.warned_ms == nil and warned.warned_ms != nil,
            do: warning(acc, company, account, warned),
            else: acc

        if Dormancy.due?(warned, now) do
          {:ok, acc, _} =
            TijaraTides.Domain.Services.Bankruptcy.bankrupt(acc, account, "dormant", now)

          TijaraTides.Domain.Services.Auctions.reconcile(acc, catalogue, company["id"])
        else
          acc
        end
      else
        acc
      end
    end)
  end

  def visit(state, account, now) do
    company = get(state, "companies", account["company_id"])

    if company && company["bankruptcy_ms"] == nil do
      old = record(state, company, now)

      if old.warned_ms != nil or get(state, "company_dormancy", company["id"]) == nil or
           now - old.last_visit_ms >= 60_000 do
        state =
          put(state, "company_dormancy", company["id"], Dormancy.to_row(Dormancy.visit(old, now)))

        if old.warned_ms != nil, do: cancel_warning(state, company["id"], old), else: state
      else
        state
      end
    else
      state
    end
  end

  def record_closure(state, account_id, company_id, escrow, now) do
    account = AccountWorld.fetch(state, account_id)
    record = Dormancy.from_row(get(state, "company_dormancy", company_id))
    company = get(state, "companies", company_id)

    unless Dormancy.due?(record, now) and company["bankruptcy_ms"] != nil,
      do: raise(ArgumentError, "Dormant closure must enter receivership exactly once")

    account = Account.detach_dormant(account, company_id)

    record = %{
      record
      | closed_ms: now,
        guarantee_id: if(escrow, do: elem(escrow, 0)),
        guaranteed_debt: if(escrow, do: elem(escrow, 1), else: 0)
    }

    state
    |> put("accounts", account_id, Account.Rows.encode(account))
    |> put("company_dormancy", company_id, Dormancy.to_row(record))
    |> delete("company_activity", company_id)
    |> cancel_warning(company_id, record)
  end

  def cancel_pending(state, company_id) do
    case get(state, "company_dormancy", company_id) do
      %{"warned_ms" => warned, "closed_ms" => nil} = row when warned != nil ->
        record = Dormancy.from_row(row)

        state
        |> cancel_warning(company_id, record)
        |> put(
          "company_dormancy",
          company_id,
          Dormancy.to_row(%{record | warned_ms: nil, closes_ms: nil})
        )

      _ ->
        state
    end
  end

  defp record(state, company, now) do
    case get(state, "company_dormancy", company["id"]) do
      nil -> Dormancy.new(company["id"], company["account_id"], now)
      row -> Dormancy.from_row(row)
    end
  end

  defp email_id(company, record), do: "dormancy:" <> company <> ":" <> to_string(record.warned_ms)

  defp cancel_warning(state, company, record) do
    state = delete(state, "notices", "dormancy:" <> company)
    id = email_id(company, record)

    state =
      case get(state, "email_requests", id) do
        %{"delivery" => "pending"} = row ->
          put(state, "email_requests", id, %{row | "delivery" => "ignored"})

        _ ->
          state
      end

    Notices.rebuild_index(state)
  end

  defp warning(state, company, account, record) do
    state =
      Notices.notice(
        state,
        account["id"],
        "dormancy:" <> company["id"],
        {"company.dormancy_warning",
         %{"company" => company["name"], "deadline" => record.closes_ms}}
      )

    if account["email"] do
      id = email_id(company["id"], record)

      put(state, "email_requests", id, %{
        "id" => id,
        "token_hash" => id,
        "email" => account["email"],
        "purpose" => "dormancy",
        "account_id" => account["id"],
        "requester" => company["id"],
        "created_ms" => record.warned_ms,
        "expires_ms" => record.closes_ms,
        "used_session" => nil,
        "attempts" => 0,
        "retry_ms" => 0,
        "delivery" => "pending"
      })
    else
      state
    end
  end
end
