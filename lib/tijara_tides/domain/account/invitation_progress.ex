defmodule TijaraTides.Domain.Account.InvitationProgress do
  @moduledoc "Population-scaled invitation accrual from explicit activity, solvency and capacity facts."
  @day_ms 86_400_000
  @limit 3
  # Integer arithmetic keeps powers of two exact without floating-point rounding.
  # An empty world has no eligible company, but still needs a readable forecast.
  def period_ms(active_companies) when is_integer(active_companies) and active_companies >= 0,
    do: max(0, length(Integer.digits(max(1, active_companies), 2)) - 1) * @day_ms

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

  def within_activity?(row, now),
    do: row["active_until_ms"] > row["checked_ms"] and now <= row["active_until_ms"]

  def advance(row, company, now, eligible?, active?, capacity, period_ms) do
    same_company? = row["company_id"] == company
    row = if row["company_id"] == company, do: row, else: new(row["account_id"], company, now)
    elapsed = max(0, min(now, row["active_until_ms"]) - row["checked_ms"])
    credit = if eligible? and capacity > 0, do: row["progress_ms"] + elapsed, else: 0
    earning? = eligible? and capacity > 0

    earned =
      cond do
        period_ms > 0 -> min(capacity, div(credit, period_ms))
        earning? and (active? or (same_company? and within_activity?(row, now))) -> capacity
        true -> 0
      end

    progress =
      if period_ms == 0 or earned == capacity or now > row["active_until_ms"],
        do: 0,
        else: rem(credit, period_ms)

    next = %{
      row
      | "checked_ms" => now,
        "progress_ms" => progress,
        "active_until_ms" =>
          if(active?,
            do: max(row["active_until_ms"], now + period_ms),
            else: row["active_until_ms"]
          )
    }

    {next, earned}
  end
end
