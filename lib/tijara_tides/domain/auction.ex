defmodule TijaraTides.Domain.Auction do
  @moduledoc "Typed auction root and bid transitions. No world-state access or row conversion."
  alias __MODULE__.{Admission, Bid, Transition}

  @fields ~w(id company_id warehouse_id port good quantity reserve opens_ms closes_ms status price winner_id valuation_seed)a
  @enforce_keys @fields
  defstruct @fields ++ [bids: %{}]

  def schedule(clock, offset, interval, window) do
    true = is_integer(interval) and interval > 0 and is_integer(window) and window > 0
    true = is_integer(offset) and offset >= 0 and offset < interval

    opens =
      if clock < offset, do: offset, else: offset + (div(clock - offset, interval) + 1) * interval

    {opens, opens + window}
  end

  def list(%__MODULE__{} = a, clock) do
    unless a.status == "scheduled" and a.bids == %{} and
             is_nil(a.price) and is_nil(a.winner_id) and
             is_integer(a.opens_ms) and a.opens_ms > clock and
             is_integer(a.closes_ms) and a.closes_ms > a.opens_ms and
             is_binary(a.valuation_seed) and (is_nil(a.company_id) or a.valuation_seed != ""),
           do: raise(ArgumentError, "A new auction requires a future bidding window and no bids")

    terms!(a.quantity, a.reserve)
    a
  end

  def revise(%__MODULE__{} = a, quantity, reserve, clock) do
    scheduled!(a)

    unless clock < a.opens_ms,
      do: raise(ArgumentError, "An auction cannot be revised after bidding opens")

    terms!(quantity, reserve)
    %{a | quantity: quantity, reserve: reserve}
  end

  def cancel(%__MODULE__{} = a), do: %{scheduled!(a) | status: "cancelled"}
  def close_unsold(%__MODULE__{} = a, clock), do: %{due!(a, clock) | status: "unsold"}

  def close_sold(%__MODULE__{} = a, price, %Bid{} = winner, clock) do
    due!(a, clock)
    recorded = bids(a)

    unless is_integer(price) and price >= a.reserve and winner in recorded and
             is_integer(winner.amount) and price <= winner.amount and
             winner.company_id != a.company_id and
             Enum.all?(recorded, &(&1.amount <= winner.amount)),
           do:
             raise(
               ArgumentError,
               "A sale requires an eligible winning bid covering the clearing price"
             )

    %{a | status: "sold", price: price, winner_id: winner.company_id}
  end

  def bids(%__MODULE__{} = a), do: Map.values(a.bids)
  def bid(_a, company) when not is_binary(company), do: nil
  def bid(%__MODULE__{} = a, company), do: Enum.find(bids(a), &(&1.company_id == company))
  def open?(%__MODULE__{} = a), do: a.status == "scheduled"

  def prepare_bid(
        %__MODULE__{} = a,
        company,
        warehouse,
        amount,
        request_id,
        %Admission{} = context
      ) do
    previous = bid(a, company)

    with {:ok, proposed} <-
           Bid.offer(
             a,
             previous,
             request_id,
             company,
             warehouse,
             amount,
             context.clock_ms,
             context.revision
           ) do
      if previous == nil and
           (context.id_taken? or Map.has_key?(a.bids, proposed.id) or capped?(a, context)),
         do: {:error, :auction_invalid},
         else: {:ok, proposed}
    end
  end

  def accept_bid(%__MODULE__{} = a, %Bid{} = proposed, %Admission{} = context) do
    unless bid(a, proposed.company_id) == nil and not Map.has_key?(a.bids, proposed.id) and
             not context.id_taken?,
           do: raise(ArgumentError, "An existing bid must be replaced explicitly")

    validate_prepared!(a, nil, proposed, context)

    if capped?(a, context),
      do: raise(ArgumentError, "A new bid exceeds the current auction or company cap")

    record(a, [proposed])
  end

  def replace_bid(%__MODULE__{} = a, %Bid{} = previous, %Bid{} = proposed, %Admission{} = context) do
    unless Map.get(a.bids, previous.id) == previous and
             proposed.id == previous.id and proposed.auction_id == previous.auction_id and
             proposed.company_id == previous.company_id,
           do:
             raise(
               ArgumentError,
               "Bid replacement requires the current accepted terms and identity"
             )

    validate_prepared!(a, previous, proposed, context)
    record(a, [proposed])
  end

  def withdraw_bid(%__MODULE__{} = a, %Bid{} = bid, clock) do
    scheduled!(a)

    unless clock < a.closes_ms and bid.kind == :player,
      do: raise(ArgumentError, "A player bid cannot be withdrawn after closing")

    remove(a, bid)
  end

  def invalidate_bid(%__MODULE__{} = a, %Bid{} = bid) do
    scheduled!(a)
    remove(a, bid)
  end

  def record_simulated_bids(%__MODULE__{} = a, bids, clock, occupied_ids) do
    due!(a, clock)

    unless length(Enum.uniq_by(bids, & &1.id)) == length(bids),
      do: raise(ArgumentError, "Simulated bid identifiers must be unique")

    Enum.each(bids, fn %Bid{} = bid ->
      unless bid == Bid.simulated(a, bid.priority_seq, bid.amount) and
               not Map.has_key?(a.bids, bid.id) and not MapSet.member?(occupied_ids, bid.id),
             do: raise(ArgumentError, "Only new simulated bids may be recorded at settlement")
    end)

    record(a, bids)
  end

  defp validate_prepared!(a, previous, proposed, context) do
    unless proposed.auction_id == a.id and
             Bid.offer(
               a,
               previous,
               proposed.id,
               proposed.company_id,
               proposed.warehouse_id,
               proposed.amount,
               context.clock_ms,
               context.revision
             ) == {:ok, proposed},
           do: raise(ArgumentError, "Bid terms or priority are no longer valid")
  end

  defp capped?(a, context), do: map_size(a.bids) >= 1000 or context.company_bid_count >= 100

  defp record(a, bids) do
    updated = Enum.reduce(bids, a.bids, &Map.put(&2, &1.id, &1))
    %Transition{auction: %{a | bids: updated}, bids_to_record: bids}
  end

  defp remove(a, bid) do
    unless bid.auction_id == a.id and Map.get(a.bids, bid.id) == bid,
      do: raise(ArgumentError, "Bid removal requires the current accepted terms")

    %Transition{auction: %{a | bids: Map.delete(a.bids, bid.id)}, bids_to_remove: [bid]}
  end

  defp scheduled!(%__MODULE__{status: "scheduled"} = a), do: a
  defp scheduled!(_), do: raise(ArgumentError, "Only a scheduled auction can transition")

  defp due!(a, clock) do
    scheduled!(a)

    unless clock >= a.closes_ms,
      do: raise(ArgumentError, "An auction cannot settle before its closing time")

    a
  end

  defp terms!(quantity, reserve) do
    unless is_integer(quantity) and quantity in 1..TijaraTides.Domain.CargoRules.max_lots() and
             is_integer(reserve) and reserve > 0,
           do:
             raise(ArgumentError, "Auction terms require a bounded quantity and positive reserve")
  end
end
