defmodule TijaraTides.Domain.Services.Bankruptcy do
  @moduledoc "Atomic receivership across financial balances, ship automation and account lifecycle."
  import TijaraTides.Domain.State, only: [get: 3, entities: 2]
  alias TijaraTides.Domain.{CompanyFinance, Account, Ship}
  alias TijaraTides.Domain.CompanyFinance.Guarantees

  def bankrupt(state, account, reason \\ "voluntary") do
    company = get(state, "companies", account["company_id"])

    cond do
      is_nil(company) or company["account_id"] != account["id"] or company["bankruptcy_ms"] != nil ->
        {:error, :finance_no_company}

      reason == "voluntary" and not CompanyFinance.can_declare_bankruptcy?(state, account) ->
        {:error, :bankruptcy_cash_covers_debts}

      true ->
        debt =
          Enum.sum(
            for loan <- CompanyFinance.loans(state, company["id"]),
                do: loan["remaining"] + loan["interest_due"] + loan["interest_accrued"]
          )

        # The escrow belongs to the sponsor's books. Record what it owes and let the
        # sponsor's own settlement forfeit it; this transaction stays single-company.
        escrow =
          case Guarantees.active(state, account["id"]) do
            nil -> nil
            guarantee -> {guarantee["id"], min(guarantee["amount"], debt)}
          end

        state = CompanyFinance.close_in_receivership(state, company["id"])

        state =
          Enum.reduce(entities(state, "ships"), state, fn {id, ship}, acc ->
            if ship["company_id"] == company["id"], do: Ship.cancel_automation(acc, id), else: acc
          end)

        state =
          Account.record_bankruptcy(
            state,
            account["id"],
            company["id"],
            reason,
            CompanyFinance.terms().cooldown_ms,
            escrow
          )

        {:ok, state, %{"bankrupt" => company["id"]}}
    end
  end
end
