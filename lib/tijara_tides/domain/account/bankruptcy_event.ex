defmodule TijaraTides.Domain.Account.BankruptcyEvent do
  @moduledoc "One company closure and its restart and guarantee facts."
  defstruct [
    :id,
    :company_id,
    :account_id,
    :created_ms,
    :restart_ms,
    :reason,
    :guarantee_id,
    :guaranteed_debt
  ]
end
