defmodule TijaraTides.Domain.Auction.BidRows do
  @moduledoc "Codec at the existing world-state boundary; Bid itself never consumes row maps."
  alias TijaraTides.Domain.Auction.Bid
  @fields ~w(id auction_id company_id warehouse_id amount priority_ms priority_seq)a
  @keys Enum.map(@fields, &Atom.to_string/1)

  def decode(row) do
    unless Enum.sort(Map.keys(row)) == Enum.sort(@keys),
      do: raise(ArgumentError, "Bid row must contain exactly the persisted bid fields")

    struct!(
      Bid,
      Map.put(
        Map.new(@fields, &{&1, Map.fetch!(row, Atom.to_string(&1))}),
        :kind,
        Bid.kind(Map.fetch!(row, "company_id"))
      )
    )
  end

  def encode(%Bid{} = bid),
    do: Map.new(@fields, &{Atom.to_string(&1), Map.fetch!(bid, &1)})
end
