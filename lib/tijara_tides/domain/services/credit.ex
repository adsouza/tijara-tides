defmodule TijaraTides.Domain.Services.Credit do
  alias TijaraTides.Domain.CompanyFinanceWorld
  @moduledoc "Credit workflow coordinates company finances with sponsor obligations."
  alias TijaraTides.Domain.Services.FinancialSettlement

  def borrow(state, account, amount, id) do
    state = FinancialSettlement.settle(state, [account["company_id"]])

    CompanyFinanceWorld.borrow(state, account, amount, id)
  end

  def repay(state, account, id), do: repay_or_recast(state, account, {:repay, id})

  def recast(state, account, id, amount),
    do: repay_or_recast(state, account, {:recast, id, amount})

  defp repay_or_recast(state, account, operation) do
    state = FinancialSettlement.settle(state, [account["company_id"]])

    result =
      case operation do
        {:repay, id} -> CompanyFinanceWorld.repay(state, account, id)
        {:recast, id, amount} -> CompanyFinanceWorld.recast(state, account, id, amount)
      end

    with {:ok, changed, reply} <- result do
      {:ok, FinancialSettlement.settle(changed, [account["company_id"]]), reply}
    end
  end
end
