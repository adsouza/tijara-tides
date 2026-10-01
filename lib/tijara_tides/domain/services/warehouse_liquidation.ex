defmodule TijaraTides.Domain.Services.WarehouseLiquidation do
  @moduledoc "Expired-lease sales and one durable, capped accounting pool per lease."
  alias TijaraTides.Domain.{
    State,
    Warehouse,
    WarehouseWorld,
    Auction,
    AuctionWorld,
    CompanyFinanceWorld,
    Notices,
    CargoRules
  }

  alias TijaraTides.Domain.Services.{Exchange, Auctions}

  alias TijaraTides.Domain.WarehouseLiquidationWorld, as: Pools
  defdelegate terms(catalogue), to: Pools
  defdelegate pool(state, id), to: Pools
  defdelegate active?(state, id), to: Pools
  defdelegate before_remove(state, id), to: Pools

  def prepare(state, w, catalogue) do
    state = Pools.prepare(state, w, catalogue)

    if active?(state, w.id) do
      Enum.reduce(
        TijaraTides.Domain.OrderBookWorld.company_orders(state, w.company_id),
        state,
        fn o, s ->
          if o.warehouse_id == w.id and o.side == "buy" do
            {:ok, s, _} = Exchange.cancel(s, %{"company_id" => w.company_id}, o.id)
            s
          else
            s
          end
        end
      )
    else
      state
    end
  end

  def refresh(state, id, catalogue) do
    if active?(state, id) do
      w = WarehouseWorld.fetch(state, id)

      blocks =
        div(
          Warehouse.volume(w, catalogue) + Warehouse.block_litres() - 1,
          Warehouse.block_litres()
        )

      state |> Pools.occupancy(id, blocks) |> WarehouseWorld.resize_expired(id, blocks)
    else
      state
    end
  end

  def record_sale(state, id, cargo, proceeds, handling \\ 0) do
    p = pool(state, id)
    cost = Enum.sum(for b <- cargo, do: b.quantity * b.unit_cost)

    state
    |> CompanyFinanceWorld.post(p["company_id"], "warehouse_liquidation_sale", [
      {"inventory", -cost},
      {"cost_of_goods", cost},
      {"sales_revenue", -proceeds},
      {"cash_reserved", proceeds}
    ])
    |> Pools.sale(id, proceeds, handling)
  end

  def advance(state, id, catalogue) do
    case pool(state, id) do
      %{"status" => status} = p when status != "completed" ->
        w = WarehouseWorld.fetch(state, id)
        state = refresh(state, id, catalogue)

        if state.clock_ms >= p["grace_end_ms"] and state.clock_ms >= w.protected_ms do
          state = Pools.begin(state, id)
          state = cancel_owner_claims(state, w)

          state =
            w.cargo
            |> Enum.map(& &1.good)
            |> Enum.uniq()
            |> Enum.sort()
            |> Enum.reduce(state, fn good, s -> liquidate_good(s, id, good, catalogue) end)

          finish(state, id)
        else
          state
        end

      _ ->
        state
    end
  end

  defp cancel_owner_claims(state, w) do
    state =
      Enum.reduce(
        TijaraTides.Domain.OrderBookWorld.company_orders(state, w.company_id),
        state,
        fn o, s ->
          if o.warehouse_id == w.id do
            {:ok, s, _} = Exchange.cancel(s, %{"company_id" => w.company_id}, o.id)
            s
          else
            s
          end
        end
      )

    WarehouseWorld.release_collection_claims(state, w.id)
  end

  def available(state, id, good) do
    w = WarehouseWorld.fetch(state, id)

    Enum.sum(for b <- Warehouse.unreserved_cargo(w, good, state.clock_ms), do: b.quantity)
  end

  defp liquidate_good(state, id, good, catalogue) do
    state = Exchange.liquidate_stock(state, id, good, catalogue)
    list_lots(state, id, good, catalogue, 50)
  end

  defp list_lots(state, _, _, _, 0), do: state

  defp list_lots(state, id, good, catalogue, budget) do
    w = WarehouseWorld.fetch(state, id)
    n = min(available(state, id, good), CargoRules.max_lots())

    if n == 0 do
      state
    else
      p = pool(state, id)
      item = catalogue["goods"][good]

      expires =
        Warehouse.unreserved_cargo(w, good, state.clock_ms)
        |> Enum.filter(
          &(&1.good == good and (&1.expires_ms == nil or &1.expires_ms > state.clock_ms))
        )
        |> Enum.map(& &1.expires_ms)
        |> Enum.reject(&is_nil/1)
        |> Enum.min(fn -> nil end)

      {opens, closes} =
        if expires,
          do: {state.clock_ms + 1, state.clock_ms + 1 + p["window_ms"]},
          else: AuctionWorld.schedule(state.clock_ms, w.port, catalogue)

      cond do
        expires && expires <= closes ->
          # FEFO clearance drains only the endangered batches, not later-lived cargo.
          quantity =
            Enum.sum(
              for b <- Warehouse.unreserved_cargo(w, good, state.clock_ms),
                  b.good == good and b.expires_ms != nil and b.expires_ms <= closes and
                    b.expires_ms > state.clock_ms,
                  do: b.quantity
            )

          state
          |> clear(id, good, min(n, quantity), catalogue)
          |> list_lots(id, good, catalogue, budget - 1)

        Enum.count(AuctionWorld.company_auctions(state, w.company_id), &AuctionWorld.open?/1) >=
            Auctions.open_limit() ->
          state

        true ->
          auction_id =
            "liquidation:#{id}:#{good}:#{state.clock_ms}:#{String.pad_leading(Integer.to_string(50 - budget), 2, "0")}"

          a = %Auction{
            id: auction_id,
            company_id: w.company_id,
            warehouse_id: id,
            port: w.port,
            good: good,
            quantity: n,
            reserve: max(1, div(n * item["reference_cents"] * p["clearance_bps"], 10_000)),
            opens_ms: opens,
            closes_ms: closes,
            status: "scheduled",
            price: nil,
            winner_id: nil,
            valuation_seed: auction_id,
            liquidation_id: id,
            expires_ms: expires
          }

          {:ok, state} = WarehouseWorld.back_order(state, Auctions.claim(a), catalogue)
          state |> AuctionWorld.list(a) |> list_lots(id, good, catalogue, budget - 1)
      end
    end
  end

  def take(state, id, good, n, catalogue) do
    state = before_remove(state, id)
    {state, cargo} = WarehouseWorld.liquidation_out(state, id, good, n)
    {refresh(state, id, catalogue), cargo}
  end

  def clear(state, id, good, n, catalogue) do
    {state, cargo} = take(state, id, good, n, catalogue)
    clear_cargo(state, id, cargo, catalogue)
  end

  defp clear_cargo(state, id, cargo, catalogue) do
    p = pool(state, id)
    good = hd(cargo).good
    item = catalogue["goods"][good]

    {state, value} =
      Enum.reduce(cargo, {state, 0}, fn batch, {s, paid} ->
        {fresh, shelf} = TijaraTides.Domain.CargoFreshness.ratio(batch, s.clock_ms, item)
        numerator = batch.quantity * item["reference_cents"] * p["clearance_bps"] * fresh
        {s, amount} = Pools.clearance_value(s, id, good, numerator, 10_000 * shelf)
        {s, paid + amount}
      end)

    record_sale(
      state,
      id,
      cargo,
      value,
      Enum.sum(for b <- cargo, do: b.quantity * p["handling_rate"])
    )
  end

  def unsold(state, a, catalogue) do
    # Consume the lot while its claim still identifies its FEFO allocation. Releasing
    # the claim first would let clearance take stock promised to another auction.
    {state, cargo} = WarehouseWorld.exchange_out(state, Auctions.claim(a), a.quantity)

    state
    |> refresh(a.liquidation_id, catalogue)
    |> clear_cargo(a.liquidation_id, cargo, catalogue)
  end

  def finish(state, id) do
    p = pool(state, id)
    w = WarehouseWorld.fetch(state, id)

    if p["status"] == "liquidating" and w.cargo == [] and w.reservations == [] do
      charges = min(p["proceeds"], p["rent_due"] + p["handling_due"])
      rent = min(charges, p["rent_due"])
      net = p["proceeds"] - charges
      estate = State.get(state, "companies", w.company_id)["bankruptcy_ms"] != nil

      state
      |> CompanyFinanceWorld.post(w.company_id, "warehouse_liquidation_closed", [
        {"cash_reserved", -p["proceeds"]},
        {"rent_expense", rent},
        {"handling_expense", charges - rent},
        {if(estate, do: "receivership", else: "cash_available"), net}
      ])
      |> Pools.complete(id, charges, net, estate)
      |> WarehouseWorld.release_liquidated(id)
      |> Notices.notice(
        State.get(state, "companies", w.company_id)["account_id"],
        "warehouse:" <> id,
        {"warehouse.cleared", %{"port" => w.port, "refund" => if(estate, do: 0, else: net)}}
      )
    else
      state
    end
  end
end
