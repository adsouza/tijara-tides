defmodule TijaraTides.Domain.Warehouse.Rows do
  @moduledoc "Codec for the unchanged lease and cargo rows."
  alias TijaraTides.Domain.Warehouse
  alias TijaraTides.Domain.Ship.CargoRows

  @fields ~w(id company_id port storage good blocks started_ms expires_ms rent prepaid protected_ms)a
  @renewal_defaults [
    display_number: 1,
    renewal_rate: nil,
    next_rent: 0,
    next_days: nil,
    auto_days: nil,
    auto_cap: nil
  ]
  def decode(row) do
    unknown =
      Map.keys(row) --
        ["cargo" | Enum.map(@fields ++ Keyword.keys(@renewal_defaults), &Atom.to_string/1)]

    if unknown != [], do: raise(ArgumentError, "Unknown warehouse fields")

    struct!(
      Warehouse,
      Map.new(@fields, &{&1, Map.fetch!(row, Atom.to_string(&1))})
      |> Map.merge(
        Map.new(@renewal_defaults, fn {k, v} -> {k, Map.get(row, Atom.to_string(k), v)} end)
      )
      |> Map.put(:cargo, Enum.map(row["cargo"], &CargoRows.decode/1))
    )
  end

  def encode(%Warehouse{} = w),
    do:
      Map.new(
        @fields ++ Keyword.keys(@renewal_defaults),
        &{Atom.to_string(&1), Map.fetch!(w, &1)}
      )
      |> Map.put("cargo", Enum.map(w.cargo, &CargoRows.encode/1))
end
