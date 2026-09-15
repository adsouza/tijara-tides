defmodule TijaraTides.Domain.Account.BankruptcyRows do
  @moduledoc "Codec for the unchanged bankruptcy history."
  alias TijaraTides.Domain.Account.BankruptcyEvent
  @fields ~w(id company_id account_id created_ms restart_ms reason guarantee_id guaranteed_debt)a
  def decode(row) do
    unless Enum.sort(Map.keys(row)) == Enum.sort(Enum.map(@fields, &Atom.to_string/1)),
      do: raise(ArgumentError, "Bankruptcy row must contain exactly the persisted fields")

    struct!(BankruptcyEvent, Map.new(@fields, &{&1, Map.fetch!(row, Atom.to_string(&1))}))
  end

  def encode(%BankruptcyEvent{} = event),
    do: Map.new(@fields, &{Atom.to_string(&1), Map.fetch!(event, &1)})
end
