defmodule TijaraTides.Domain.Services.FinancialSettlement do
  @moduledoc "Coordinate owned financial transitions, receivership and guarantee release."
  alias TijaraTides.Domain.{CompanyFinance, State}
  alias TijaraTides.Domain.CompanyFinance.Guarantees
  alias TijaraTides.Domain.Services.Bankruptcy

  def settle(state, company_ids \\ :all) do
    ids =
      if company_ids == :all,
        do: Map.keys(State.entities(state, "companies")),
        else: Enum.uniq(company_ids) -- [nil]

    state = Guarantees.settle(state, company_ids)

    state =
      Enum.reduce(ids, state, fn id, state ->
        case State.get(state, "companies", id) do
          nil ->
            state

          _ ->
            {state, effects} = CompanyFinance.settle_owned(state, id)
            if effects.receivership, do: foreclose(state, id), else: state
        end
      end)

    Guarantees.settle(state, company_ids)
  end

  # Bankruptcy resolves its target from the account, so foreclose only while that
  # account still holds the company whose grace period expired. A detached or
  # reassigned owner means some other company would be closed instead.
  defp foreclose(state, id) do
    company = State.get(state, "companies", id)
    account = State.get(state, "accounts", company["account_id"])

    with true <- account != nil and account["company_id"] == id,
         {:ok, next, _} <- Bankruptcy.bankrupt(state, account, "forced") do
      next
    else
      _ -> state
    end
  end
end
