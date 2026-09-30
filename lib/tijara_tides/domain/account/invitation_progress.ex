defmodule TijaraTides.Domain.Account.InvitationProgress do
  @moduledoc "Two-day invitation accrual from explicit activity, solvency and capacity facts."
  @period_ms 2 * 86_400_000
  @limit 3
  def period_ms, do: @period_ms
  def limit, do: @limit

  def new(account, company, now) do
    %{
      "account_id" => account,
      "company_id" => company,
      "checked_ms" => now,
      "active_until_ms" => now,
      "progress_ms" => 0
    }
  end

  def advance(row, company, now, eligible?, active?, capacity) do
    row = if row["company_id"] == company, do: row, else: new(row["account_id"], company, now)
    elapsed = max(0, min(now, row["active_until_ms"]) - row["checked_ms"])
    credit = if eligible? and capacity > 0, do: row["progress_ms"] + elapsed, else: 0
    earned = min(capacity, div(credit, @period_ms))

    progress =
      if earned == capacity or now > row["active_until_ms"],
        do: 0,
        else: rem(credit, @period_ms)

    next = %{
      row
      | "checked_ms" => now,
        "progress_ms" => progress,
        "active_until_ms" => if(active?, do: now + @period_ms, else: row["active_until_ms"])
    }

    {next, earned}
  end
end
