defmodule TijaraTides.Domain.Guarantees do
  @moduledoc "Compatibility facade for CompanyFinance guarantee operations."
  defdelegate suspended?(account), to: TijaraTides.Domain.CompanyFinance.Guarantees
  defdelegate sponsor_eligible?(state, sponsor), to: TijaraTides.Domain.CompanyFinance.Guarantees
  defdelegate active(state, account_id), to: TijaraTides.Domain.CompanyFinance.Guarantees

  defdelegate pledge(state, sponsor, beneficiary_id, amount, id),
    to: TijaraTides.Domain.CompanyFinance.Guarantees

  defdelegate drawn(state, account), to: TijaraTides.Domain.CompanyFinance.Guarantees
  defdelegate settle(state), to: TijaraTides.Domain.CompanyFinance.Guarantees
  defdelegate default(state, account, debt), to: TijaraTides.Domain.CompanyFinance.Guarantees
  defdelegate view(state, account), to: TijaraTides.Domain.CompanyFinance.Guarantees
end
