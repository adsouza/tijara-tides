defmodule TijaraTides.UseCases.AuctionQueries do
  @moduledoc "Auction discovery and owner-scoped bidding options."
  alias TijaraTides.Domain.{CargoRules, Warehouse}
  alias TijaraTides.UseCases.WarehouseStorage

  # AuctionWorld.prune/1 keeps closed auctions per port, so the world-wide tail is
  # long; discovery shows the newest few plus the player's own activity, all
  # limited to the last three active-world days.
  @settled_shown 20
  @settled_window_ms 3 * 86_400_000

  def auction_discovery(view, grouping \\ "status", show_all_settled \\ false) do
    public = Map.get(view, :public, %{})
    clock = public["clock_ms"] || 0

    bids = Map.new(get_in(view, [:private, "auction_bids"]) || [], &{&1["auction_id"], &1})

    consignments = MapSet.new(get_in(view, [:private, "consignments"]) || [], & &1["id"])

    {scheduled, settled} =
      Enum.split_with(public["auctions"] || [], &(&1["status"] == "scheduled"))

    {recent, older} =
      settled
      |> Enum.filter(&(grouping != "cargo" and &1["closes_ms"] >= clock - @settled_window_ms))
      |> Enum.filter(
        &(show_all_settled or bids[&1["id"]] != nil or MapSet.member?(consignments, &1["id"]))
      )
      |> Enum.sort_by(& &1["closes_ms"], :desc)
      |> Enum.split(@settled_shown)

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

    leased = WarehouseStorage.snapshots(private, clock)

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

        # Replacing a bid releases its claim before checking any candidate warehouse,
        # including shared space in a different allocation.
        storage_models =
          if bid = bids[a["id"]],
            do: WarehouseStorage.snapshots(private, clock, bid["id"]),
            else: leased

        # A bid backs the entire lot in storage covering the close.
        storage =
          for row <- warehouses,
              w = storage_models[row["id"]],
              Warehouse.covers?(w, a["closes_ms"], clock) and Warehouse.receiving_open?(w, clock) and
                item != nil and Warehouse.compatible?(w, item) and
                Warehouse.reservation_limit(w, "capacity", item, clock, cat) >= a["quantity"],
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

    # The command backs a consignment with claimable stock in storage covering the close;
    # stock already backing auctions or exchange orders is held in reservation rows.
    consignable =
      for row <- Map.values(private["warehouses"] || %{}),
          row["port"] == port,
          lease = leased[row["id"]],
          Warehouse.covers?(lease, closes, clock),
          {good, _item} <- goods,
          quantity = Warehouse.claimable_stock(lease, good, clock),
          quantity > 0,
          do: %{warehouse: row, good: good, quantity: min(quantity, CargoRules.max_lots())}

    %{
      listings: listings,
      goods: goods,
      warehouses: warehouses,
      consignable: Enum.sort_by(consignable, &{&1.warehouse["id"], &1.good}),
      opens: opens,
      closes: closes,
      clock: clock,
      roles: cat["ports"][port]["roles"]
    }
  end
end
