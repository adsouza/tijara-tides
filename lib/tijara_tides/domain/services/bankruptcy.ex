defmodule TijaraTides.Domain.Services.Bankruptcy do
  alias TijaraTides.Domain.CompanyFinanceWorld
  alias TijaraTides.Domain.AccountWorld

  @moduledoc "Atomic receivership across financial balances, ship automation and account lifecycle."
  import TijaraTides.Domain.State, only: [get: 3, entities: 2]
  alias TijaraTides.Domain.{CompanyFinance}
  alias TijaraTides.Domain.CompanyFinanceWorld.Guarantees

  def bankrupt(state, account, reason \\ "voluntary", wall_ms \\ nil) do
    company = get(state, "companies", account["company_id"])

    cond do
      is_nil(company) or company["account_id"] != account["id"] or company["bankruptcy_ms"] != nil ->
        {:error, :finance_no_company}

      reason == "voluntary" and not CompanyFinanceWorld.can_declare_bankruptcy?(state, account) ->
        {:error, :bankruptcy_cash_covers_debts}

      true ->
        debt =
          Enum.sum(
            for loan <- CompanyFinanceWorld.loans(state, company["id"]),
                do: loan["remaining"] + loan["interest_due"] + loan["interest_accrued"]
          )

        # The escrow belongs to the sponsor's books. Record what it owes and let the
        # sponsor's own settlement forfeit it; this transaction stays single-company.
        escrow =
          case Guarantees.active(state, account["id"]) do
            nil -> nil
            guarantee -> {guarantee["id"], min(guarantee["amount"], debt)}
          end

        state = CompanyFinanceWorld.close_in_receivership(state, company["id"], reason)

        state =
          Enum.reduce(entities(state, "ships"), state, fn {id, ship}, acc ->
            if ship["company_id"] == company["id"],
              do: TijaraTides.Domain.Services.ShipLifecycle.cancel_automation(acc, id),
              else: acc
          end)

        state =
          if reason == "dormant" do
            TijaraTides.Domain.AccountWorld.Dormancy.record_closure(
              state,
              account["id"],
              company["id"],
              escrow,
              wall_ms
            )
          else
            AccountWorld.record_bankruptcy(
              state,
              account["id"],
              company["id"],
              reason,
              CompanyFinance.terms().cooldown_ms,
              escrow
            )
          end

        state =
          if reason == "dormant",
            do: TijaraTides.Domain.Services.Exchange.reconcile(state, company["id"]),
            else: state

        {:ok, state, %{if(reason == "dormant", do: "dormant", else: "bankrupt") => company["id"]}}
    end
  end
end
