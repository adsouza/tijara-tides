defmodule TijaraTides.Domain.AuctionWorld do
  @moduledoc "Integrates typed Auction transitions with the existing atomic world state. No SQL or independent commits."
  alias TijaraTides.Domain.{Auction, State}
  alias TijaraTides.Domain.Auction.{Admission, Bid, BidRows, Rows, Transition}

  def fetch(s, id) do
    case State.get(s, "auctions", id) do
      nil -> nil
      row -> %{Rows.decode(row) | bids: Map.new(bids(s, id), &{&1.id, &1})}
    end
  end

  def all(s), do: Enum.map(Map.keys(State.entities(s, "auctions")), &fetch(s, &1))

  def company_auctions(s, company),
    do: Enum.map(State.owned(s, "auctions", "company_id", company), &fetch(s, &1["id"]))

  def bids(s, id),
    do: Enum.map(State.owned(s, "auction_bids", "auction_id", id), &BidRows.decode/1)

  def company_bids(s, company),
    do: Enum.map(State.owned(s, "auction_bids", "company_id", company), &BidRows.decode/1)

  def bid(_s, _id, company) when not is_binary(company), do: nil

  def bid(s, id, company) do
    case fetch(s, id) do
      nil -> nil
      a -> Auction.bid(a, company)
    end
  end

  defdelegate open?(a), to: Auction

  def list(s, %Auction{} = a) do
    unless State.get(s, "auctions", a.id) == nil,
      do: raise(ArgumentError, "A new auction requires a unique ID")

    accepted = Auction.list(a, s.clock_ms)
    State.put(s, "auctions", a.id, Rows.encode(accepted))
  end

  def revise(s, id, quantity, reserve),
    do: update(s, id, &Auction.revise(&1, quantity, reserve, s.clock_ms))

  def cancel(s, id), do: update(s, id, &Auction.cancel/1)
  def close_unsold(s, id), do: update(s, id, &Auction.close_unsold(&1, s.clock_ms))

  def close_sold(s, id, price, winner),
    do: update(s, id, &Auction.close_sold(&1, price, winner, s.clock_ms))

  def prepare_bid(s, id, company, warehouse, amount, request_id) do
    case fetch(s, id) do
      nil ->
        {:error, :auction_invalid}

      a ->
        previous = Auction.bid(a, company)
        context = admission(s, company, if(previous, do: previous.id, else: request_id))
        Auction.prepare_bid(a, company, warehouse, amount, request_id, context)
    end
  end

  def accept_bid(s, %Bid{} = proposed),
    do:
      update(
        s,
        proposed.auction_id,
        &Auction.accept_bid(&1, proposed, admission(s, proposed.company_id, proposed.id))
      )

  def replace_bid(s, %Bid{} = previous, %Bid{} = proposed),
    do:
      update(
        s,
        proposed.auction_id,
        &Auction.replace_bid(
          &1,
          previous,
          proposed,
          admission(s, proposed.company_id, proposed.id)
        )
      )

  def withdraw_bid(s, %Bid{} = bid),
    do: update(s, bid.auction_id, &Auction.withdraw_bid(&1, bid, s.clock_ms))

  def invalidate_bid(s, %Bid{} = bid),
    do: update(s, bid.auction_id, &Auction.invalidate_bid(&1, bid))

  def record_simulated_bids(s, id, bids) do
    occupied =
      bids |> Enum.filter(&(State.get(s, "auction_bids", &1.id) != nil)) |> MapSet.new(& &1.id)

    update(s, id, &Auction.record_simulated_bids(&1, bids, s.clock_ms, occupied))
  end

  defp admission(s, company, id) do
    count =
      Enum.count(State.owned(s, "auction_bids", "company_id", company), fn b ->
        case State.get(s, "auctions", b["auction_id"]) do
          %{"status" => "scheduled"} -> true
          _ -> false
        end
      end)

    %Admission{
      clock_ms: s.clock_ms,
      revision: s.revision,
      company_bid_count: count,
      id_taken?: State.get(s, "auction_bids", id) != nil
    }
  end

  defp update(s, id, operation) do
    before = fetch(s, id) || raise ArgumentError, "Auction does not exist"

    case operation.(before) do
      %Auction{} = after_auction ->
        store_auction(s, before, after_auction)

      %Transition{} = transition ->
        s = store_auction(s, before, transition.auction)

        s =
          Enum.reduce(transition.bids_to_remove, s, fn bid, state ->
            unless bid.auction_id == id and
                     State.get(state, "auction_bids", bid.id) == BidRows.encode(bid),
                   do:
                     raise(
                       ArgumentError,
                       "Bid deletion requires current terms owned by this auction"
                     )

            State.delete(state, "auction_bids", bid.id)
          end)

        Enum.reduce(transition.bids_to_record, s, fn bid, state ->
          unless bid.auction_id == id,
            do: raise(ArgumentError, "Bid addition belongs to another auction")

          State.put(state, "auction_bids", bid.id, BidRows.encode(bid))
        end)
    end
  end

  defp store_auction(s, before, after_auction) do
    unless before.id == after_auction.id,
      do: raise(ArgumentError, "Auction identity cannot change")

    # Child omission never implies deletion; only Transition.bids_to_remove does.
    State.put(s, "auctions", before.id, Rows.encode(after_auction))
  end

  # Existing schedules are immutable; these settings apply only to new listings.
  def schedule(clock, port, catalogue) do
    config = Map.get(catalogue, "auctions", %{})
    interval = Map.get(config, "interval_ms", 86_400_000)
    window = Map.get(config, "window_ms", 86_400_000)
    true = is_integer(interval) and interval > 0 and is_integer(window) and window > 0
    ports = Enum.sort(Map.keys(catalogue["ports"]))

    offset =
      get_in(config, ["offsets", port]) ||
        div(Enum.find_index(ports, &(&1 == port)) * interval, length(ports))

    Auction.schedule(clock, offset, interval, window)
  end

  def private_bids(_s, nil), do: []

  def private_bids(s, company) do
    for b <- company_bids(s, company), a = fetch(s, b.auction_id) do
      won = a.status == "sold" and a.winner_id == company

      Map.merge(BidRows.encode(b), %{
        "status" => a.status,
        "won" => won,
        "paid" => if(won, do: a.price, else: 0)
      })
    end
  end

  def public(s) do
    Enum.map(all(s), fn a ->
      row =
        Map.take(
          Rows.encode(a),
          ~w(id port good quantity reserve opens_ms closes_ms status price)
        )

      amounts =
        if Auction.open?(a),
          do: [],
          else: Enum.sort(Enum.map(Auction.bids(a), & &1.amount), :desc)

      Map.put(row, "amounts", amounts)
    end)
  end

  def prune(s) do
    all(s)
    |> Enum.reject(&Auction.open?/1)
    |> Enum.group_by(& &1.port)
    |> Enum.reduce(s, fn {_, auctions}, state ->
      auctions
      |> Enum.sort_by(&{&1.closes_ms, &1.id}, :desc)
      |> Enum.drop(20)
      |> Enum.reduce(state, fn a, acc ->
        acc = Enum.reduce(Auction.bids(a), acc, &State.delete(&2, "auction_bids", &1.id))
        State.delete(acc, "auctions", a.id)
      end)
    end)
  end
end
