defmodule TijaraTides.Domain.Services.Bankruptcy do
  alias TijaraTides.Domain.CompanyFinanceWorld
  alias TijaraTides.Domain.AccountWorld
  alias TijaraTides.Domain.AccountWorld.Dormancy

  @moduledoc "Atomic receivership across financial balances, ship automation and account lifecycle."
  import TijaraTides.Domain.State, only: [get: 3, entities: 2]
  alias TijaraTides.Domain.{CompanyFinance}
  alias TijaraTides.Domain.CompanyFinanceWorld.Guarantees

  @doc "Absence warnings, then receivership for every company past its closure deadline."
  def advance_dormancy(state, nil, _catalogue), do: state

  def advance_dormancy(state, now, catalogue) do
    state
    |> Dormancy.advance(now, catalogue)
    |> close_dormant(Map.values(entities(state, "accounts")), now)
  end

  def advance_owner_dormancy(state, _account, nil, _catalogue), do: state

  def advance_owner_dormancy(state, account, now, catalogue) do
    state
    |> Dormancy.advance_for(account, now, catalogue)
    |> close_dormant([account], now)
  end

  defp close_dormant(state, accounts, now) do
    Enum.reduce(Dormancy.due(state, accounts, now), state, fn account, s ->
      {:ok, s, _} = bankrupt(s, get(s, "accounts", account["id"]), "dormant", now)
      s
    end)
  end

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
          |> TijaraTides.Domain.Services.Exchange.cancel_company_orders(company["id"])
          |> TijaraTides.Domain.Services.Auctions.release_company_bids(company["id"])
          |> TijaraTides.Domain.WarehouseWorld.release_insolvent_claims(company["id"])

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

        {:ok, state, %{if(reason == "dormant", do: "dormant", else: "bankrupt") => company["id"]}}
    end
  end
end
