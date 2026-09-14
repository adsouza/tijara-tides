defmodule TijaraTides.Domain.Auction.Admission do
  @moduledoc "Current facts outside one auction, supplied when planning or accepting a bid."
  @enforce_keys [:clock_ms, :revision, :company_bid_count, :id_taken?]
  defstruct @enforce_keys
end
