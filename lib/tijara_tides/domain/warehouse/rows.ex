defmodule TijaraTides.Domain.Warehouse.Rows do
  @moduledoc "Codec for lease terms, snapshotted expiry settings and cargo rows."
  alias TijaraTides.Domain.Warehouse
  alias TijaraTides.Domain.Ship.CargoRows

  @fields ~w(id company_id port storage good blocks started_ms expires_ms rent prepaid protected_ms)a
  @renewal_defaults [
    aging_bps: 2500,
    source_lease_id: nil,
    space_group: nil,
    space_volumes: %{},
    award_id: nil,
    award_grace: false,
    grace_rent: nil,
    grace_blocks: nil,
    grace_duration_ms: nil,
    display_number: 1,
    renewal_rate: nil,
    next_rent: 0,
    next_days: nil,
    auto_days: nil,
    auto_cap: nil,
    grace_ms: 43_200_000,
    surcharge_bps: 2500,
    window_ms: 7_200_000,
    clearance_bps: 1000
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
