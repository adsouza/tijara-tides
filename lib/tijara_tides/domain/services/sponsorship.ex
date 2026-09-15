defmodule TijaraTides.Domain.Services.Sponsorship do
  alias TijaraTides.Domain.AccountWorld
  @moduledoc "Coordinate a funded sponsor pledge with beneficiary reinstatement."
  alias TijaraTides.Domain.{State}
  alias TijaraTides.Domain.CompanyFinance.Guarantees
  alias TijaraTides.Domain.Services.FinancialSettlement

  def pledge(state, sponsor, beneficiary, amount, id) do
    state = FinancialSettlement.settle(state, [sponsor["company_id"]])
    sponsor = State.get(state, "accounts", sponsor["id"])

    with {:ok, changed, reply} <- Guarantees.pledge(state, sponsor, beneficiary, amount, id) do
      {:ok, AccountWorld.reinstate(changed, beneficiary, id), reply}
    end
  end
end
