defmodule TijaraTides.Domain.Auction.Transition do
  @moduledoc "An auction transition and its explicit child additions or removals."
  @enforce_keys [:auction]
  defstruct [:auction, bids_to_record: [], bids_to_remove: []]
end
