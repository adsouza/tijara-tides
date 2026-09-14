defmodule TijaraTides.Domain.Auction.Rows do
  @moduledoc "Codec for the unchanged auction row; bids are loaded separately by AuctionWorld."
  alias TijaraTides.Domain.Auction

  @fields ~w(id company_id warehouse_id port good quantity reserve opens_ms closes_ms status price winner_id valuation_seed)a
  @keys Enum.map(@fields, &Atom.to_string/1)

  def decode(row) do
    unless Enum.sort(Map.keys(row)) == Enum.sort(@keys),
      do: raise(ArgumentError, "Auction row must contain exactly the persisted auction fields")

    struct!(Auction, Map.new(@fields, &{&1, Map.fetch!(row, Atom.to_string(&1))}))
  end

  def encode(%Auction{} = auction),
    do: Map.new(@fields, &{Atom.to_string(&1), Map.fetch!(auction, &1)})
end
