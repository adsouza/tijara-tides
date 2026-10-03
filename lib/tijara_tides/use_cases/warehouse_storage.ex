defmodule TijaraTides.UseCases.WarehouseStorage do
  @moduledoc "Loads an account's leases as the commands do, from authorized read models."
  alias TijaraTides.Domain.WarehouseWorld

  @doc """
  Every lease hydrated by `WarehouseWorld.hydrate/4`, keyed by id. A replacement
  bid releases its claim before the command checks storage, so `released_bid_id`
  drops that claim first.
  """
  def snapshots(private, now, released_bid_id \\ nil) do
    rows = Map.values((private && private["warehouses"]) || %{})

    claims =
      Map.values((private && private["warehouse_reservations"]) || %{})
      |> Enum.reject(&(released_bid_id != nil and &1["bid_id"] == released_bid_id))

    Map.new(rows, &{&1["id"], WarehouseWorld.hydrate(&1, rows, claims, now)})
  end
end
