defmodule TijaraTides.UseCases.AuctionQueries do
  @moduledoc "Auction discovery and owner-scoped bidding options."

  def auction_discovery(view, grouping \\ "status") do
    public = Map.get(view, :public, %{})
    clock = public["clock_ms"] || 0

    (public["auctions"] || [])
    |> Enum.filter(&(&1["status"] == "scheduled" and &1["closes_ms"] > clock))
    |> Enum.group_by(fn a ->
      if grouping == "cargo",
        do: a["good"],
        else: if(a["opens_ms"] <= clock, do: "open", else: "upcoming")
    end)
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.map(fn {good, listings} ->
      {good,
       Enum.sort_by(listings, &{&1["opens_ms"] > clock, &1["closes_ms"], &1["port"], &1["id"]})}
    end)
  end

  def auction_options(definitions, view, port) do
    cat = definitions.catalogue
    clock = view.public["clock_ms"] || 0
    private = view.private || %{}

    warehouses =
      Map.values(private["warehouses"] || %{})
      |> Enum.filter(&(&1["port"] == port and &1["expires_ms"] > clock))
      |> Enum.sort_by(& &1["id"])

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
          Enum.filter(
            warehouses,
            &(&1["expires_ms"] >= a["closes_ms"] and &1["protected_ms"] <= clock and
                TijaraTides.Domain.Warehouse.compatible?(
                  TijaraTides.Domain.Warehouse.from_row(&1),
                  item
                ))
          )

        Map.merge(a, %{
          "mine" => Map.has_key?(consignments, a["id"]),
          "bid" => bids[a["id"]],
          "warehouses" => storage,
          "simulated" =>
            String.contains?(get_in(cat, ["ports", port, "roles", a["good"]]) || "", "imp")
        })
      end)

    {opens, closes} = TijaraTides.Domain.Auction.schedule(clock, port, cat)

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
