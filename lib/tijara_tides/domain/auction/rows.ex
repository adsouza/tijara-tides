defmodule TijaraTides.Domain.Auction.Rows do
  @moduledoc "Codec for auction terms and optional liquidation metadata; bids are loaded separately by AuctionWorld."
  alias TijaraTides.Domain.Auction

  @fields ~w(id company_id warehouse_id port good quantity reserve opens_ms closes_ms status price winner_id valuation_seed)a
  @keys Enum.map(@fields, &Atom.to_string/1)

  def decode(row) do
    unless Enum.sort(Map.keys(Map.drop(row, ~w(ship_id liquidation_id expires_ms)))) ==
             Enum.sort(@keys),
           do:
             raise(ArgumentError, "Auction row must contain exactly the persisted auction fields")

    struct!(
      Auction,
      Map.new(@fields, &{&1, Map.fetch!(row, Atom.to_string(&1))})
      |> Map.merge(
        Map.new(~w(ship_id liquidation_id expires_ms)a, &{&1, row[Atom.to_string(&1)]})
      )
    )
  end

  def encode(%Auction{} = auction),
    do:
      Map.new(@fields, &{Atom.to_string(&1), Map.fetch!(auction, &1)})
      |> then(fn row ->
        Enum.reduce(~w(ship_id liquidation_id expires_ms)a, row, fn key, row ->
          if Map.fetch!(auction, key) != nil,
            do: Map.put(row, Atom.to_string(key), Map.fetch!(auction, key)),
            else: row
        end)
      end)
end
