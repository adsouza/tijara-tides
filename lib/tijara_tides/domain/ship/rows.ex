defmodule TijaraTides.Domain.Ship.Rows do
  @moduledoc "Codec for the unchanged hull and cargo representation."
  alias TijaraTides.Domain.Ship
  alias TijaraTides.Domain.Ship.CargoRows

  @fields ~w(voyage_path paid_canals id company_id name class book_value build_value built_ms port cargo status arrive_ms destination depart_ms fuel_total fuel_burned crew_remainder last_cost_ms last_liquid voyage_speedup berth_queued_ms berth_granted_ms berth_retry_ms pending_side pending_good pending_quantity pending_limit pending_destination)a
  def decode(row) do
    struct!(Ship, Map.new(@fields, &{&1, row[Atom.to_string(&1)]}))
    |> Map.update!(:cargo, &Enum.map(&1 || [], fn batch -> CargoRows.decode(batch) end))
  end

  def encode(%Ship{} = ship) do
    Map.new(@fields, &{Atom.to_string(&1), Map.fetch!(ship, &1)})
    |> Map.put("cargo", Enum.map(ship.cargo, &CargoRows.encode/1))
    |> Map.reject(fn {key, value} ->
      is_nil(value) and
        key in ~w(voyage_path paid_canals berth_queued_ms berth_granted_ms berth_retry_ms pending_side pending_good pending_quantity pending_limit pending_destination)
    end)
    |> then(fn row ->
      if ship.voyage_speedup == nil, do: Map.delete(row, "voyage_speedup"), else: row
    end)
  end
end
