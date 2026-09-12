defmodule TijaraTides.Domain.Services.Credit do
  @moduledoc "Credit workflow coordinates company finances with sponsor obligations."
  alias TijaraTides.Domain.CompanyFinance
  alias TijaraTides.Domain.Services.FinancialSettlement

  def borrow(state, account, amount, id) do
    state = FinancialSettlement.settle(state, [account["company_id"]])

    CompanyFinance.borrow(state, account, amount, id)
  end

  def repay(state, account, id), do: repay_or_recast(state, account, {:repay, id})

  def recast(state, account, id, amount),
    do: repay_or_recast(state, account, {:recast, id, amount})

  defp repay_or_recast(state, account, operation) do
    state = FinancialSettlement.settle(state, [account["company_id"]])

    result =
      case operation do
        {:repay, id} -> CompanyFinance.repay(state, account, id)
        {:recast, id, amount} -> CompanyFinance.recast(state, account, id, amount)
      end

    with {:ok, changed, reply} <- result do
      {:ok, FinancialSettlement.settle(changed, [account["company_id"]]), reply}
    end
  end
end
