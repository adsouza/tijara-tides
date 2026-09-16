defmodule TijaraTides.Domain.Services.Estates do
  @moduledoc "Receiver choreography: unload, offer once, settle or scrap, then close the cash estate."
  alias TijaraTides.Domain.{
    Auction,
    AuctionWorld,
    CompanyFinanceWorld,
    ShipWorld,
    WarehouseWorld,
    Warehouse
  }

  alias TijaraTides.Domain.Services.Auctions
  import TijaraTides.Domain.ReadState

  def estate?(s, company),
    do: company != nil and get(s, "companies", company)["bankruptcy_ms"] != nil

  def excluded?(s, auction, company) do
    estate?(s, auction.company_id) and
      get(s, "companies", auction.company_id)["account_id"] ==
        get(s, "companies", company)["account_id"]
  end

  def advance(s, cat) do
    s =
      Enum.reduce(Enum.sort(entities(s, "ships")), s, fn {id, ship}, s ->
        if estate?(s, ship["company_id"]) and ship["status"] == "docked" do
          case ship["cargo"] do
            [] ->
              list_ship(s, ship, cat)

            [batch | _] ->
              WarehouseWorld.estate_unload(
                s,
                get(s, "ships", id),
                cat["goods"][batch["good"]],
                cat
              )
          end
        else
          s
        end
      end)

    s =
      Enum.reduce(Enum.sort(entities(s, "warehouses")), s, fn {id, row}, s ->
        if estate?(s, row["company_id"]) do
          # Preserve commitments already accepting bids, including expired leases.
          closes =
            AuctionWorld.company_auctions(s, row["company_id"])
            |> Enum.filter(&(&1.warehouse_id == id and AuctionWorld.open?(&1)))
            |> Enum.map(& &1.closes_ms)

          s = if closes == [], do: s, else: WarehouseWorld.estate_cover(s, id, Enum.max(closes))
          w = WarehouseWorld.fetch(s, id)

          if w.protected_ms <= s.clock_ms do
            w.cargo
            |> Enum.map(& &1.good)
            |> Enum.uniq()
            |> Enum.sort()
            |> Enum.reduce(s, &list_cargo(&2, id, &1, cat))
          else
            s
          end
        else
          s
        end
      end)

    Enum.reduce(entities(s, "companies"), s, fn {id, c}, s ->
      assets =
        Enum.any?(entities(s, "ships"), fn {_, r} -> r["company_id"] == id end) or
          Enum.any?(entities(s, "warehouses"), fn {_, r} -> r["company_id"] == id end)

      free = c["cash"] - c["reserved"]

      if c["bankruptcy_ms"] != nil and not assets and free > 0,
        do:
          CompanyFinanceWorld.post(s, id, "estate_closed", [
            {"cash_available", -free},
            {"receivership", free}
          ]),
        else: s
    end)
  end

  defp list_ship(s, ship, cat) do
    id = "estate-ship:" <> ship["company_id"] <> ":" <> ship["id"]

    if AuctionWorld.fetch(s, id) do
      s
    else
      {opens, closes} = AuctionWorld.schedule(s.clock_ms, ship["port"], cat)

      AuctionWorld.list(s, %Auction{
        id: id,
        company_id: ship["company_id"],
        warehouse_id: nil,
        ship_id: ship["id"],
        port: ship["port"],
        good: ship["class"],
        quantity: 1,
        reserve: max(1, div(ship["book_value"], 10)),
        opens_ms: opens,
        closes_ms: closes,
        status: "scheduled",
        price: nil,
        winner_id: nil,
        valuation_seed: id
      })
    end
  end

  defp list_cargo(s, id, good, cat) do
    w = WarehouseWorld.fetch(s, id)

    fresh =
      Enum.filter(
        w.cargo,
        &(&1.good == good and (is_nil(&1.expires_ms) or &1.expires_ms > s.clock_ms))
      )

    quantity =
      Enum.sum(Enum.map(fresh, & &1.quantity)) - Warehouse.reserved_quantity(w, "stock", good)

    if quantity <= 0 do
      s
    else
      {normal_open, normal_close} = AuctionWorld.schedule(s.clock_ms, w.port, cat)
      expiry = fresh |> Enum.map(&(&1.expires_ms || normal_close + 1)) |> Enum.min()
      urgent = expiry <= normal_close
      opens = if urgent, do: s.clock_ms + 1, else: normal_open
      closes = if urgent, do: min(expiry - 1, opens + 7_200_000), else: normal_close
      # Goods with less than a full expedited window are disposed of immediately.
      immediate = urgent and closes < opens + 7_200_000
      s = WarehouseWorld.estate_cover(s, id, max(closes, s.clock_ms + 1))

      a = %Auction{
        id: "estate-cargo:#{id}:#{good}:#{s.clock_ms}",
        company_id: w.company_id,
        warehouse_id: id,
        port: w.port,
        good: good,
        quantity: min(quantity, 10_000),
        reserve: max(1, div(cat["goods"][good]["reference_cents"] * min(quantity, 10_000), 10)),
        opens_ms: opens,
        closes_ms: max(opens + 1, closes),
        status: "scheduled",
        price: nil,
        winner_id: nil,
        valuation_seed: "estate:#{id}:#{good}"
      }

      {:ok, s} = WarehouseWorld.back_order(s, Auctions.claim(a), cat)

      if immediate do
        dispose_cargo(s, a)
      else
        AuctionWorld.list(s, a)
      end
    end
  end

  def dispose_cargo(s, a) do
    {s, cargo} = WarehouseWorld.exchange_out(s, Auctions.claim(a), a.quantity)
    cost = Enum.sum(Enum.map(cargo, &(&1.quantity * &1.unit_cost)))

    CompanyFinanceWorld.post(s, a.company_id, "estate_cargo_disposal", [
      {"inventory", -cost},
      {"receivership", cost}
    ])
  end

  def dispose_ship(s, a) do
    ship = get(s, "ships", a.ship_id)

    s
    |> ShipWorld.retire(a.ship_id)
    |> CompanyFinanceWorld.post(a.company_id, "estate_ship_disposal", [
      {"fleet", -ship["book_value"]},
      {"receivership", ship["book_value"]}
    ])
  end
end
