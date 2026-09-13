defmodule TijaraTides.Domain.Warehouse.Claim do
  @moduledoc "One party's exclusive hold on a lease's stock or receiving space."
  @kinds [:order, :auction, :bid]
  @fields ~w(id kind company_id warehouse_id good quantity side closes_ms)a
  @enforce_keys ~w(id kind warehouse_id good quantity side)a
  defstruct @fields

  def new(fields) do
    claim = struct!(__MODULE__, Keyword.put_new(fields, :closes_ms, nil))

    unless claim.kind in @kinds and claim.side in ["buy", "sell"] and is_binary(claim.id),
      do: raise(ArgumentError, "Unknown warehouse claim")

    claim
  end

  # The stored prefixes predate this struct; keeping them keeps existing rows addressable.
  def reservation_id(%__MODULE__{kind: :order, id: id}), do: "exchange:" <> id
  def reservation_id(%__MODULE__{kind: :auction, id: id}), do: "auction_id:" <> id
  def reservation_id(%__MODULE__{kind: :bid, id: id}), do: "bid_id:" <> id

  @doc "Whether this claim owns that reservation column; exactly one is ever set."
  def owner(%__MODULE__{kind: kind}, kind), do: true
  def owner(%__MODULE__{}, _), do: false
end
