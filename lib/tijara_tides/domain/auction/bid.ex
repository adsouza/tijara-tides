defmodule TijaraTides.Domain.Auction.Bid do
  @moduledoc "Sealed bid terms and priority rules, independent of world rows and persistence."
  @enforce_keys [
    :id,
    :auction_id,
    :company_id,
    :warehouse_id,
    :amount,
    :priority_ms,
    :priority_seq,
    :kind
  ]
  defstruct @enforce_keys
  @type t :: %__MODULE__{}

  @doc "The one place a stored bid's variant is inferred from its absent company."
  def kind(nil), do: :simulated
  def kind(company) when is_binary(company), do: :player

  def offer(auction, previous, id, company, warehouse, amount, clock, revision) do
    if auction.status == "scheduled" and clock >= auction.opens_ms and clock < auction.closes_ms and
         is_binary(company) and company != auction.company_id and
         ((is_nil(auction.ship_id) and is_binary(warehouse)) or
            (auction.ship_id != nil and is_nil(warehouse))) and
         is_binary(id) and is_integer(amount) and amount in 1..1_000_000_000_000 and
         amount >= auction.reserve do
      retained = previous && previous.amount == amount

      {:ok,
       %__MODULE__{
         kind: :player,
         id: if(previous, do: previous.id, else: id),
         auction_id: auction.id,
         company_id: company,
         warehouse_id: warehouse,
         amount: amount,
         priority_ms: if(retained, do: previous.priority_ms, else: clock),
         priority_seq: if(retained, do: previous.priority_seq, else: revision)
       }}
    else
      {:error, :auction_invalid}
    end
  end

  def simulated(auction, index, amount) do
    unless is_binary(auction.company_id) and is_integer(index) and index in 1..20 and
             is_integer(amount) and amount >= auction.reserve,
           do:
             raise(
               ArgumentError,
               "Simulated bids require a player lot, bidder index and reserve coverage"
             )

    %__MODULE__{
      kind: :simulated,
      id: "npc:#{auction.id}:#{index}",
      auction_id: auction.id,
      company_id: nil,
      warehouse_id: nil,
      amount: amount,
      priority_ms: auction.closes_ms,
      priority_seq: index
    }
  end

  def priority(%__MODULE__{} = bid),
    do: {-bid.amount, bid.priority_ms, bid.priority_seq, bid.id}
end
