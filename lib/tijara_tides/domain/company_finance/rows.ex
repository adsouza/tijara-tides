defmodule TijaraTides.Domain.CompanyFinance.Rows do
  @moduledoc "Codec for the unchanged company balances and lifecycle fields."
  alias TijaraTides.Domain.CompanyFinance

  @fields ~w(id cash reserved unpaid profit account_id name created_ms last_invite_year unpaid_since arrears_since bankruptcy_ms)a
  @enforce_keys [:id, :cash, :reserved, :unpaid, :profit]
  def decode(row) do
    unknown = Map.keys(row) -- Enum.map(@fields, &Atom.to_string/1)
    if unknown != [], do: raise(ArgumentError, "Unknown company fields: #{inspect(unknown)}")

    struct!(
      CompanyFinance,
      Map.new(@fields, fn key ->
        value =
          if key in @enforce_keys,
            do: Map.fetch!(row, Atom.to_string(key)),
            else: row[Atom.to_string(key)]

        {key, value}
      end)
    )
  end

  def encode(%CompanyFinance{} = finance),
    do: Map.new(@fields, &{Atom.to_string(&1), Map.fetch!(finance, &1)})
end
