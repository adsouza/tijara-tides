defmodule TijaraTides.Domain.MerchantWarehouse do
  @moduledoc "Paid, good-specific merchant storage in the same finite pools as player leases."
  @day 86_400_000
  @fields ~w(id port good storage blocks capacity expires_ms)a
  @enforce_keys @fields
  defstruct @fields ++ [protected_ms: 0]

  def open?(w, now), do: w.expires_ms > now and w.protected_ms <= now
  def covers?(w, close), do: w.expires_ms > close
  def free(w, stock), do: max(0, w.capacity - stock)
  def overdue_days(w, now), do: div(max(0, now - w.expires_ms) + @day - 1, @day)
  def cleared?(w, now), do: now >= w.expires_ms + div(@day, 2) and now >= w.protected_ms
  def protect(w, until_ms), do: %{w | protected_ms: max(w.protected_ms, until_ms)}
end

defmodule TijaraTides.Domain.MerchantWarehouse.Rows do
  @moduledoc "Codec for paid NPC storage leases."
  alias TijaraTides.Domain.MerchantWarehouse
  @fields ~w(id port good storage blocks capacity expires_ms)a
  def decode(row),
    do:
      struct!(
        MerchantWarehouse,
        Map.new(@fields, &{&1, Map.fetch!(row, Atom.to_string(&1))})
        |> Map.put(:protected_ms, Map.get(row, "protected_ms", 0))
      )

  def encode(w), do: Map.new(@fields ++ [:protected_ms], &{Atom.to_string(&1), Map.fetch!(w, &1)})
end
