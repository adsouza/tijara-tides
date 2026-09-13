defmodule TijaraTides.Domain.Warehouse.Reservation do
  @moduledoc "A ship's claim to owned stock or receiving volume, managed by its warehouse root."
  @fields ~w(id warehouse_id company_id ship_id good kind quantity created_ms stop_id)a
  @enforce_keys @fields
  defstruct @fields ++ [order_id: nil, auction_id: nil, bid_id: nil]

  def from_row(row) do
    if Map.keys(row) -- Enum.map([:order_id, :auction_id, :bid_id | @fields], &Atom.to_string/1) !=
         [],
       do: raise(ArgumentError, "Unknown warehouse reservation fields")

    struct!(
      __MODULE__,
      Map.new(@fields, &{&1, Map.fetch!(row, Atom.to_string(&1))})
      |> Map.put(:order_id, row["order_id"])
      |> Map.put(:auction_id, row["auction_id"])
      |> Map.put(:bid_id, row["bid_id"])
    )
  end

  def to_row(r),
    do:
      Map.new(
        [:order_id, :auction_id, :bid_id | @fields],
        &{Atom.to_string(&1), Map.fetch!(r, &1)}
      )
end
