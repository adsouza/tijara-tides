defmodule TijaraTides.Domain.Warehouse.ReservationRows do
  @moduledoc "Codec for persisted warehouse claims."
  alias TijaraTides.Domain.Warehouse.Reservation
  @fields ~w(id warehouse_id company_id ship_id good kind quantity created_ms stop_id)a
  def decode(row) do
    if Map.keys(row) -- Enum.map([:order_id, :auction_id, :bid_id | @fields], &Atom.to_string/1) !=
         [],
       do: raise(ArgumentError, "Unknown warehouse reservation fields")

    struct!(
      Reservation,
      Map.new(@fields, &{&1, Map.fetch!(row, Atom.to_string(&1))})
      |> Map.put(:order_id, row["order_id"])
      |> Map.put(:auction_id, row["auction_id"])
      |> Map.put(:bid_id, row["bid_id"])
    )
  end

  def encode(%Reservation{} = r),
    do:
      Map.new(
        [:order_id, :auction_id, :bid_id | @fields],
        &{Atom.to_string(&1), Map.fetch!(r, &1)}
      )
end
