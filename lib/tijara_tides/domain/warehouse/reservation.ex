defmodule TijaraTides.Domain.Warehouse.Reservation do
  @moduledoc "A ship's claim to owned stock or receiving volume, managed by its warehouse root."
  @fields ~w(id warehouse_id company_id ship_id good kind quantity created_ms stop_id)a
  @enforce_keys @fields
  # expires_ms is derived from immutable auction terms when the world loads claims.
  defstruct @fields ++ [order_id: nil, auction_id: nil, bid_id: nil, expires_ms: nil]
end
