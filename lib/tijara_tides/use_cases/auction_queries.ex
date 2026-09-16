defmodule TijaraTides.UseCases.AuctionQueries do
  @moduledoc "Auction discovery and owner-scoped bidding options."
  alias TijaraTides.Domain.{Warehouse, WarehouseWorld}

  # AuctionWorld.prune/1 keeps closed auctions per port, so the world-wide tail is
  # long; discovery shows the newest few plus the player’s own bids and consignments.
  @settled_shown 20

  def auction_discovery(view, grouping \\ "status") do
    public = Map.get(view, :public, %{})
    clock = public["clock_ms"] || 0

    bids = Map.new(get_in(view, [:private, "auction_bids"]) || [], &{&1["auction_id"], &1})

    consignments = MapSet.new(get_in(view, [:private, "consignments"]) || [], & &1["id"])

    {scheduled, settled} =
      Enum.split_with(public["auctions"] || [], &(&1["status"] == "scheduled"))

    {recent, older} =
      settled |> Enum.sort_by(& &1["closes_ms"], :desc) |> Enum.split(@settled_shown)

    (Enum.filter(scheduled, &(&1["closes_ms"] > clock)) ++
       recent ++ Enum.filter(older, &(bids[&1["id"]] || MapSet.member?(consignments, &1["id"]))))
    |> Enum.map(&Map.put(&1, "bid", bids[&1["id"]]))
    |> Enum.group_by(fn a ->
      if grouping == "cargo", do: a["good"], else: discovery_status(a, clock)
    end)
    |> Enum.sort_by(fn {group, _} ->
      if grouping == "cargo",
        do: group,
        else: Enum.find_index(["open", "upcoming", "settled"], &(&1 == group))
    end)
    |> Enum.map(fn {group, listings} ->
      {group,
       Enum.sort_by(listings, fn a ->
         {if(a["status"] == "scheduled", do: 0, else: 1),
          a["status"] == "scheduled" and a["opens_ms"] > clock,
          if(a["status"] == "scheduled", do: a["closes_ms"], else: -a["closes_ms"]), a["port"],
          a["id"]}
       end)}
    end)
  end

  defp discovery_status(%{"status" => "scheduled"} = a, clock),
    do: if(a["opens_ms"] <= clock, do: "open", else: "upcoming")

  defp discovery_status(_, _), do: "settled"

  def auction_options(definitions, view, port) do
    cat = definitions.catalogue
    clock = view.public["clock_ms"] || 0
    private = view.private || %{}

    warehouses =
      Map.values(private["warehouses"] || %{})
      |> Enum.filter(&(&1["port"] == port and &1["expires_ms"] > clock))
      |> Enum.sort_by(& &1["id"])

    # Decode each lease once here rather than once per listing in the filter below.
    leased = Enum.map(warehouses, &{&1, WarehouseWorld.snapshot(&1)})

    goods =
      Enum.filter(cat["goods"], fn {_, i} -> i["category"] == "Luxury items" end) |> Enum.sort()

    consignments = Map.new(private["consignments"] || [], &{&1["id"], &1})
    bids = Map.new(private["auction_bids"] || [], &{&1["auction_id"], &1})

    listings =
      (view.public["auctions"] || [])
      |> Enum.filter(&(&1["port"] == port))
      |> Enum.sort_by(
        &{if(&1["status"] == "scheduled", do: 0, else: 1), &1["closes_ms"], &1["id"]}
      )

    listings =
      Enum.map(listings, fn a ->
        item = cat["goods"][a["good"]]

        storage =
          for {row, w} <- leased,
              Warehouse.covered_until(w) >= a["closes_ms"] and row["protected_ms"] <= clock and
                item != nil and Warehouse.compatible?(w, item),
              do: row

        Map.merge(a, %{
          "mine" => Map.has_key?(consignments, a["id"]),
          "bid" => bids[a["id"]],
          "warehouses" => storage,
          "simulated" =>
            String.contains?(get_in(cat, ["ports", port, "roles", a["good"]]) || "", "imp")
        })
      end)

    {opens, closes} = TijaraTides.Domain.AuctionWorld.schedule(clock, port, cat)

    %{
      listings: listings,
      goods: goods,
      warehouses: warehouses,
      opens: opens,
      closes: closes,
      clock: clock,
      roles: cat["ports"][port]["roles"]
    }
  end
end
