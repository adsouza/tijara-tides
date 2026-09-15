defmodule TijaraTides.Domain.Account.BankruptcyRows do
  @moduledoc "Codec for the unchanged bankruptcy history."
  alias TijaraTides.Domain.Account.BankruptcyEvent
  @fields ~w(id company_id account_id created_ms restart_ms reason guarantee_id guaranteed_debt)a
  def decode(row), do: struct!(BankruptcyEvent, Map.new(@fields, &{&1, row[Atom.to_string(&1)]}))

  def encode(%BankruptcyEvent{} = event),
    do: Map.new(@fields, &{Atom.to_string(&1), Map.fetch!(event, &1)})
end
