defmodule TijaraTides.Domain.CompanyFinance.LoanActions do
  @moduledoc "Shared repayment/recast eligibility and amount bounds, expressed in integer cents."

  def for_loan(company, loan) do
    free = if company, do: max(0, company["cash"] - company["reserved"]), else: 0
    active = company != nil and company["bankruptcy_ms"] == nil and loan["status"] == "open"
    payoff = loan["remaining"] + loan["interest_due"] + loan["interest_accrued"]
    minimum = loan["interest_accrued"] + 100
    maximum = min(free, loan["remaining"] + loan["interest_accrued"])

    recast_allowed =
      active and loan["periods_left"] > 0 and loan["principal_due"] == 0 and
        loan["interest_due"] == 0 and company["unpaid"] == 0

    %{
      "repay_enabled" => active and free >= payoff,
      "payoff" => payoff,
      "recast_allowed" => recast_allowed,
      "recast_enabled" => recast_allowed and maximum >= minimum,
      "recast_min" => minimum,
      "recast_max" => maximum,
      "recast_balance" => loan["remaining"] + loan["interest_accrued"]
    }
  end
end
