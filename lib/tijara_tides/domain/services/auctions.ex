defmodule TijaraTides.Domain.Services.Auctions do
  alias TijaraTides.Domain.CompanyFinanceWorld
  alias TijaraTides.Domain.WarehouseWorld
  alias TijaraTides.Domain.Ship.CargoRows
  alias TijaraTides.Domain.PortCargoMarketWorld
  @moduledoc "Atomic luxury-auction scheduling, escrow and second-price settlement."
  import TijaraTides.Domain.ReadState, only: [get: 3]
  alias TijaraTides.Domain.{Notices}
  alias TijaraTides.Domain.AuctionWorld
  alias TijaraTides.Domain.Auction
  alias TijaraTides.Domain.Ship.CargoBatch
  alias TijaraTides.Domain.Auction.Bid
  alias TijaraTides.Domain.Warehouse.Claim
  @max_lots TijaraTides.Domain.CargoRules.max_lots()

  defp live?(s, id) do
    case is_binary(id) && get(s, "companies", id) do
      nil -> false
      false -> false
      company -> company["bankruptcy_ms"] == nil
    end
  end

  defp amount?(n), do: is_integer(n) and n in 1..1_000_000_000_000
  defp quantity?(n), do: is_integer(n) and n in 1..@max_lots

  defp reserve(s, company, n),
    do:
      CompanyFinanceWorld.post(s, company, "auction_escrow", [
        {"cash_available", -n},
        {"cash_reserved", n}
      ])

  def claim(a),
    do:
      Claim.new(
        id: a.id,
        kind: :auction,
        company_id: a.company_id,
        warehouse_id: a.warehouse_id,
        good: a.good,
        quantity: a.quantity,
        side: "sell",
        closes_ms: a.closes_ms
      )

  def bid_claim(a, b),
    do:
      Claim.new(
        id: b.id,
        kind: :bid,
        company_id: b.company_id,
        warehouse_id: b.warehouse_id,
        good: a.good,
        quantity: a.quantity,
        side: "buy",
        closes_ms: a.closes_ms
      )

  def consign(s, account, cmd, id, cat, seed) when is_binary(seed) and seed != "" do
    w = get(s, "warehouses", cmd["warehouse"])
    item = cat["goods"][cmd["good"]]

    if w && w["company_id"] == account["company_id"] && live?(s, account["company_id"]) && item &&
         item["category"] == "Luxury items" && quantity?(cmd["quantity"]) && amount?(cmd["price"]) &&
         AuctionWorld.fetch(s, id) == nil &&
         Enum.count(
           AuctionWorld.all(s),
           &(&1.company_id == account["company_id"] and AuctionWorld.open?(&1))
         ) < 50 do
      {opens, closes} = AuctionWorld.schedule(s.clock_ms, w["port"], cat)

      a = %Auction{
        id: id,
        company_id: w["company_id"],
        warehouse_id: w["id"],
        port: w["port"],
        good: item["id"],
        quantity: cmd["quantity"],
        reserve: cmd["price"],
        opens_ms: opens,
        closes_ms: closes,
        status: "scheduled",
        price: nil,
        winner_id: nil,
        valuation_seed: seed
      }

      with :ok <- coverage(s, w, a),
           {:ok, s} <- WarehouseWorld.back_order(s, claim(a), cat),
           do: {:ok, AuctionWorld.list(s, a), %{}}
    else
      {:error, :auction_invalid}
    end
  end

  def revise(s, account, cmd, cat) do
    a = AuctionWorld.fetch(s, cmd["auction"])

    if a && AuctionWorld.open?(a) && s.clock_ms < a.opens_ms &&
         a.company_id == account["company_id"] &&
         live?(s, a.company_id) && quantity?(cmd["quantity"]) && amount?(cmd["price"]) do
      revised = AuctionWorld.revise(s, a.id, cmd["quantity"], cmd["price"])
      updated = AuctionWorld.fetch(revised, a.id)

      with {:ok, next} <-
             WarehouseWorld.back_order(
               WarehouseWorld.release_trade(revised, claim(a)),
               claim(updated),
               cat
             ),
           do: {:ok, next, %{}}
    else
      {:error, :auction_locked}
    end
  end

  def withdraw_lot(s, account, id) do
    a = AuctionWorld.fetch(s, id)

    if a && AuctionWorld.open?(a) && a.company_id == account["company_id"] &&
         s.clock_ms < a.opens_ms,
       do: {:ok, cancel(s, a), %{}},
       else: {:error, :auction_locked}
  end

  def bid(s, account, cmd, id, cat) do
    a = AuctionWorld.fetch(s, cmd["auction"])
    w = get(s, "warehouses", cmd["warehouse"])
    company = account["company_id"]

    if a && live?(s, company) && w && w["company_id"] == company && w["port"] == a.port do
      old = AuctionWorld.bid(s, a.id, company)

      with {:ok, b} <- AuctionWorld.prepare_bid(s, a.id, company, w["id"], cmd["price"], id) do
        next = if old, do: release_bid(s, a, old), else: s
        c = get(next, "companies", company)

        cond do
          c["cash"] - c["reserved"] < b.amount or
              (c["unpaid"] > 0 and b.amount > ((old && old.amount) || 0)) ->
            {:error, :insufficient_cash}

          true ->
            with :ok <- coverage(next, w, a),
                 {:ok, next} <- WarehouseWorld.back_order(next, bid_claim(a, b), cat),
                 do: {:ok, next |> reserve(company, b.amount) |> accept_prepared_bid(old, b), %{}}
        end
      end
    else
      {:error, :auction_invalid}
    end
  end

  defp accept_prepared_bid(s, nil, proposed), do: AuctionWorld.accept_bid(s, proposed)

  defp accept_prepared_bid(s, previous, proposed),
    do: AuctionWorld.replace_bid(s, previous, proposed)

  def withdraw_bid(s, account, id) do
    a = AuctionWorld.fetch(s, id)
    b = a && AuctionWorld.bid(s, id, account["company_id"])

    if b && AuctionWorld.open?(a) && s.clock_ms < a.closes_ms,
      do: {:ok, s |> release_bid(a, b) |> AuctionWorld.withdraw_bid(b), %{}},
      else: {:error, :auction_locked}
  end

  defp coverage(s, w, a) do
    if w["expires_ms"] >= a.closes_ms && w["protected_ms"] <= s.clock_ms,
      do: :ok,
      else: {:error, :auction_storage}
  end

  defp release_bid(s, a, b),
    do: s |> WarehouseWorld.release_trade(bid_claim(a, b)) |> reserve(b.company_id, -b.amount)

  defp cancel(s, a) do
    s =
      Enum.reduce(AuctionWorld.bids(s, a.id), s, fn b, s ->
        s |> release_bid(a, b) |> AuctionWorld.invalidate_bid(b)
      end)

    s = if a.company_id, do: WarehouseWorld.release_trade(s, claim(a)), else: s
    AuctionWorld.cancel(s, a.id)
  end

  # Runs before lease liquidation, including on a tick that crosses the closing time.
  def advance(s, cat), do: s |> reconcile(cat) |> seed(cat) |> AuctionWorld.prune()

  def reconcile(s, cat), do: sweep(s, cat, AuctionWorld.all(s))

  @doc "Post-command sweep: the acting company's own lots and the ones it has bid on."
  def reconcile(s, _cat, nil), do: s

  def reconcile(s, cat, company_id) do
    mine = AuctionWorld.company_auctions(s, company_id)

    bid_on =
      for b <- AuctionWorld.company_bids(s, company_id),
          a = AuctionWorld.fetch(s, b.auction_id),
          do: a

    sweep(s, cat, Enum.uniq_by(mine ++ bid_on, & &1.id))
  end

  defp sweep(s, cat, auctions) do
    s =
      Enum.reduce(
        auctions |> Enum.filter(&AuctionWorld.open?/1) |> Enum.sort_by(&{&1.closes_ms, &1.id}),
        s,
        fn a, s ->
          cond do
            a.company_id &&
                (not live?(s, a.company_id) or not WarehouseWorld.order_backed?(s, claim(a))) ->
              cancel(s, a)

            s.clock_ms >= a.closes_ms ->
              close(s, a, cat)

            true ->
              Enum.reduce(AuctionWorld.bids(s, a.id), s, fn b, s ->
                if not live?(s, b.company_id) or
                     not WarehouseWorld.order_backed?(s, bid_claim(a, b)),
                   do: s |> release_bid(a, b) |> AuctionWorld.invalidate_bid(b),
                   else: s
              end)
          end
        end
      )

    s
  end

  defp seed(s, cat) do
    luxury =
      Enum.filter(cat["goods"], fn {_, item} -> item["category"] == "Luxury items" end)
      |> Enum.sort()

    outstanding =
      AuctionWorld.all(s)
      |> Enum.filter(&(&1.company_id == nil and AuctionWorld.open?(&1)))
      |> Enum.group_by(&{&1.port, &1.good})

    supplier_lots = get_in(cat, ["auctions", "supplier_lots"]) || 5
    true = is_integer(supplier_lots) and supplier_lots in 1..@max_lots

    Enum.reduce(Enum.sort(cat["ports"]), s, fn {port, _}, s ->
      Enum.reduce(luxury, s, fn {good, _item}, s ->
        market = get(s, "markets", port <> "|" <> good)
        {opens, closes} = AuctionWorld.schedule(s.clock_ms, port, cat)
        id = "npc-auction:#{port}:#{good}:#{opens}"

        active = Map.get(outstanding, {port, good}, [])

        available =
          if market, do: market["stock"] - Enum.sum(Enum.map(active, & &1.quantity)), else: 0

        if market && market["seller"] && available > 0 &&
             length(active) < 4 && AuctionWorld.fetch(s, id) == nil do
          n = min(available, supplier_lots)
          q = PortCargoMarketWorld.quote(s, cat, port, good)

          AuctionWorld.list(s, %Auction{
            id: id,
            company_id: nil,
            warehouse_id: nil,
            port: port,
            good: good,
            quantity: n,
            reserve: max(1, q["ask"] * n),
            opens_ms: opens,
            closes_ms: closes,
            status: "scheduled",
            price: nil,
            winner_id: nil,
            valuation_seed: ""
          })
        else
          s
        end
      end)
    end)
  end

  defp npc_bids(s, a, cat) do
    m = get(s, "markets", a.port <> "|" <> a.good)
    # A supplier cannot compete for its own lot. Buyers consume finite demand and
    # budget at close; deterministic private valuations keep replanning reproducible.
    if a.company_id && m && m["buyer"] && m["demand"] >= a.quantity do
      q = PortCargoMarketWorld.quote(s, cat, a.port, a.good)
      count = get_in(cat, ["auctions", "simulated_bidders"]) || 3
      spread = get_in(cat, ["auctions", "valuation_spread_percent"]) || 20
      true = is_integer(count) and count in 1..20 and is_integer(spread) and spread in 0..100

      for i <- 1..count,
          value =
            div(
              q["bid"] * a.quantity *
                (100 - spread + :erlang.phash2({a.valuation_seed, a.id, i}, 2 * spread + 1)),
              100
            ),
          value >= a.reserve and value <= m["budget"],
          do: Bid.simulated(a, i, value)
    else
      []
    end
  end

  defp close(s, a, cat) do
    {eligible, invalid} =
      Enum.split_with(
        AuctionWorld.bids(s, a.id),
        &(live?(s, &1.company_id) and WarehouseWorld.order_backed?(s, bid_claim(a, &1)))
      )

    s =
      Enum.reduce(invalid, s, fn b, s ->
        s |> release_bid(a, b) |> AuctionWorld.invalidate_bid(b)
      end)

    bids =
      Enum.sort_by(
        eligible ++ npc_bids(s, a, cat),
        &Bid.priority/1
      )

    if bids == [] or not suppliable?(s, a) do
      # Supplier stock is listed, not held, so ordinary trading can drain it before the
      # close. Settle as unsold rather than asking the market for cargo it no longer has.
      s = Enum.reduce(eligible, s, &release_bid(&2, a, &1))
      s = if a.company_id, do: WarehouseWorld.release_trade(s, claim(a)), else: s
      AuctionWorld.close_unsold(s, a.id)
    else
      [winner | others] = bids
      price = max(a.reserve, if(others == [], do: a.reserve, else: hd(others).amount))

      {s, cargo} =
        if a.company_id do
          {s, batches} = WarehouseWorld.exchange_out(s, claim(a), a.quantity)
          cost = Enum.sum(Enum.map(batches, &(&1.quantity * &1.unit_cost)))

          s =
            CompanyFinanceWorld.post(s, a.company_id, "auction_sale", [
              {"inventory", -cost},
              {"cost_of_goods", cost},
              {"sales_revenue", -price},
              {"cash_available", price}
            ])

          {s, batches}
        else
          {s, rows} =
            PortCargoMarketWorld.auction_supply(
              s,
              a.port,
              a.good,
              a.quantity,
              price,
              cat["goods"][a.good]
            )

          {s, Enum.map(rows, &CargoRows.decode/1)}
        end

      s =
        if winner.kind == :player do
          {s, cargo} = reprice(s, cargo, a, price)

          s
          |> WarehouseWorld.exchange_in(bid_claim(a, winner), cargo, a.quantity)
          |> CompanyFinanceWorld.post(winner.company_id, "auction_purchase", [
            {"cash_reserved", -winner.amount},
            {"cash_available", winner.amount - price},
            {"inventory", price}
          ])
        else
          PortCargoMarketWorld.auction_consume(s, a.port, a.good, a.quantity, price)
        end

      s =
        Enum.reduce(eligible, s, fn b, s ->
          if b.id != winner.id, do: release_bid(s, a, b), else: s
        end)

      s = AuctionWorld.record_simulated_bids(s, a.id, Enum.filter(bids, &(&1.kind == :simulated)))
      s = AuctionWorld.close_sold(s, a.id, price, winner)

      Enum.reduce(
        Enum.uniq([a.company_id | Enum.map(eligible, & &1.company_id)]),
        s,
        fn company, s ->
          if company,
            do:
              Notices.notice(
                s,
                get(s, "companies", company)["account_id"],
                "auction:#{a.id}:#{company}",
                {"auction.closed", %{"port" => a.port}}
              ),
            else: s
        end
      )
    end
  end

  defp suppliable?(_s, %{company_id: owner}) when not is_nil(owner), do: true

  defp suppliable?(s, a) do
    m = get(s, "markets", a.port <> "|" <> a.good)
    m != nil and m["seller"] and m["stock"] >= a.quantity
  end

  defp reprice(s, batches, a, price) do
    extra = rem(price, a.quantity)

    if extra == 0 do
      {s, Enum.map(batches, &CargoRows.encode(%{&1 | unit_cost: div(price, a.quantity)}))}
    else
      {s, high, low} = CargoBatch.take(s, batches, extra, a.good)

      {s,
       Enum.map(high, &CargoRows.encode(%{&1 | unit_cost: div(price, a.quantity) + 1})) ++
         Enum.map(low, &CargoRows.encode(%{&1 | unit_cost: div(price, a.quantity)}))}
    end
  end
end
