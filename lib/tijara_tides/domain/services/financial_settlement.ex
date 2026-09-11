defmodule TijaraTides.Domain.Services.FinancialSettlement do
  @moduledoc "Coordinate owned financial transitions, receivership and guarantee release."
  alias TijaraTides.Domain.{CompanyFinance, State}
  alias TijaraTides.Domain.CompanyFinance.Guarantees

  def settle(state, company_ids \\ :all) do
    ids =
      if company_ids == :all,
        do: Map.keys(State.entities(state, "companies")),
        else: Enum.uniq(company_ids) -- [nil]

    state =
      Enum.reduce(ids, state, fn id, state ->
        case State.get(state, "companies", id) do
          nil ->
            state

          _ ->
            {state, effects} = CompanyFinance.settle_owned(state, id)

            if effects.receivership do
              company = State.get(state, "companies", id)
              account = State.get(state, "accounts", company["account_id"])

              {:ok, next, _} =
                TijaraTides.Domain.Services.Bankruptcy.bankrupt(state, account, "forced")

              next
            else
              state
            end
        end
      end)

    Guarantees.settle(state, company_ids)
  end
end
