defmodule TijaraTides.Domain.Ship.Rows do
  @moduledoc "Codec for the unchanged hull and cargo representation."
  alias TijaraTides.Domain.Ship
  alias TijaraTides.Domain.Ship.CargoRows

  @fields ~w(voyage_path paid_canals id company_id name class book_value build_value built_ms port cargo status arrive_ms destination depart_ms fuel_total fuel_burned crew_remainder last_cost_ms last_liquid voyage_speedup berth_queued_ms berth_granted_ms berth_retry_ms pending_side pending_good pending_quantity pending_limit pending_destination)a
  # The only fields encode/1 may omit; every other column must be present to decode.
  @optional ~w(voyage_path paid_canals voyage_speedup berth_queued_ms berth_granted_ms berth_retry_ms pending_side pending_good pending_quantity pending_limit pending_destination cargo)a
  @optional_keys Enum.map(@optional, &Atom.to_string/1)
  @required @fields -- @optional

  def decode(row) do
    unknown = Map.keys(row) -- Enum.map(@fields, &Atom.to_string/1)
    if unknown != [], do: raise(ArgumentError, "Unknown ship fields: #{inspect(unknown)}")

    Map.new(@required, &{&1, Map.fetch!(row, Atom.to_string(&1))})
    |> Map.merge(Map.new(@optional, &{&1, row[Atom.to_string(&1)]}))
    |> Map.update!(:cargo, &Enum.map(&1 || [], fn batch -> CargoRows.decode(batch) end))
    |> then(&struct!(Ship, &1))
  end

  def encode(%Ship{} = ship) do
    Map.new(@fields, &{Atom.to_string(&1), Map.fetch!(ship, &1)})
    |> Map.put("cargo", Enum.map(ship.cargo, &CargoRows.encode/1))
    |> Map.reject(fn {key, value} -> is_nil(value) and key in @optional_keys end)
  end
end
