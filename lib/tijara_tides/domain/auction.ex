defmodule TijaraTides.Domain.Auction do
  @moduledoc "Scheduled luxury consignments and sealed company bids."
  import TijaraTides.Domain.State

  @fields ~w(id company_id warehouse_id port good quantity reserve opens_ms closes_ms status price winner_id valuation_seed)a
  @enforce_keys @fields
  defstruct @fields

  def from_row(row),
    do: struct!(__MODULE__, Map.new(@fields, &{&1, Map.fetch!(row, Atom.to_string(&1))}))

  def to_row(a), do: Map.new(@fields, &{Atom.to_string(&1), Map.fetch!(a, &1)})
  def all(s), do: Enum.map(Map.values(entities(s, "auctions")), &from_row/1)

  def fetch(s, id) do
    case get(s, "auctions", id) do
      nil -> nil
      row -> from_row(row)
    end
  end

  def save(s, a), do: put(s, "auctions", a.id, to_row(a))
  def bids(s, id), do: owned(s, "auction_bids", "auction_id", id)
  def bid(s, id, company), do: Enum.find(bids(s, id), &(&1["company_id"] == company))
  def put_bid(s, b), do: put(s, "auction_bids", b["id"], b)
  def delete_bid(s, id), do: delete(s, "auction_bids", id)
  def open?(a), do: a.status == "scheduled"

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

    true = is_integer(offset) and offset >= 0 and offset < interval

    opens =
      if clock < offset, do: offset, else: offset + (div(clock - offset, interval) + 1) * interval

    {opens, opens + window}
  end

  def private_bids(_s, nil), do: []

  def private_bids(s, company) do
    for b <- owned(s, "auction_bids", "company_id", company), a = fetch(s, b["auction_id"]) do
      won = a.status == "sold" and a.winner_id == company
      Map.merge(b, %{"status" => a.status, "won" => won, "paid" => if(won, do: a.price, else: 0)})
    end
  end

  def public(s) do
    Enum.map(all(s), fn a ->
      row = Map.take(to_row(a), ~w(id port good quantity reserve opens_ms closes_ms status price))

      amounts =
        if open?(a), do: [], else: Enum.sort(Enum.map(bids(s, a.id), & &1["amount"]), :desc)

      Map.put(row, "amounts", amounts)
    end)
  end

  def prune(s) do
    all(s)
    |> Enum.reject(&open?/1)
    |> Enum.group_by(& &1.port)
    |> Enum.reduce(s, fn {_, rows}, s ->
      rows
      |> Enum.sort_by(&{&1.closes_ms, &1.id}, :desc)
      |> Enum.drop(20)
      |> Enum.reduce(s, fn a, s ->
        s = Enum.reduce(bids(s, a.id), s, &delete_bid(&2, &1["id"]))
        delete(s, "auctions", a.id)
      end)
    end)
  end
end
