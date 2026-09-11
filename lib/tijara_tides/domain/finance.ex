defmodule TijaraTides.Domain.Finance do
  @moduledoc "Compatibility facade; financial rules belong to CompanyFinance."
  defdelegate terms(), to: TijaraTides.Domain.CompanyFinance
  defdelegate rate(state, account), to: TijaraTides.Domain.CompanyFinance
  defdelegate credit_limit(state, account), to: TijaraTides.Domain.CompanyFinance
  defdelegate history(state, account), to: TijaraTides.Domain.CompanyFinance
  defdelegate counted(state, account), to: TijaraTides.Domain.CompanyFinance
  defdelegate restart_at(state, account), to: TijaraTides.Domain.CompanyFinance
  defdelegate loans(state, company), to: TijaraTides.Domain.CompanyFinance
  defdelegate summary(state, account), to: TijaraTides.Domain.CompanyFinance
  defdelegate borrow(state, account, amount, id), to: TijaraTides.Domain.CompanyFinance
  defdelegate repay(state, account, id), to: TijaraTides.Domain.CompanyFinance
  defdelegate recast(state, account, id, amount), to: TijaraTides.Domain.CompanyFinance
  defdelegate settle(state), to: TijaraTides.Domain.CompanyFinance
  defdelegate operating_bill(state, company, amount, due), to: TijaraTides.Domain.CompanyFinance
  defdelegate can_declare_bankruptcy?(state, account), to: TijaraTides.Domain.CompanyFinance
  defdelegate bankrupt(state, account, reason), to: TijaraTides.Domain.CompanyFinance
  def bankrupt(state, account), do: bankrupt(state, account, "voluntary")
end
