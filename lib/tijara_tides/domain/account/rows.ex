defmodule TijaraTides.Domain.Account.Rows do
  @moduledoc "Codec for the unchanged account row and locale fallback."
  alias TijaraTides.Domain.Account

  @fields ~w(id company_id inviter bankruptcies suspended_ms email invite_quota created_ms locale)a
  def decode(row) do
    unless Enum.sort(Map.keys(row)) == Enum.sort(Enum.map(@fields, &Atom.to_string/1)),
      do: raise(ArgumentError, "Account row must contain exactly the persisted account fields")

    struct!(
      Account,
      Map.new(
        @fields,
        &{&1,
         if(&1 == :locale,
           do: Map.fetch!(row, "locale") || "en",
           else: Map.fetch!(row, Atom.to_string(&1))
         )}
      )
    )
  end

  def encode(%Account{} = account),
    do:
      Map.new(
        @fields,
        &{Atom.to_string(&1),
         if(&1 == :locale, do: account.locale || "en", else: Map.fetch!(account, &1))}
      )
end
