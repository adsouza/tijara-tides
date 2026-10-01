defmodule TijaraTides.Domain.Services.Exchange do
  alias TijaraTides.Domain.CompanyFinanceWorld
  alias TijaraTides.Domain.WarehouseWorld
  alias TijaraTides.Domain.Ship.CargoRows
  alias TijaraTides.Domain.PortCargoMarketWorld
  alias TijaraTides.Domain.OrderBookWorld
  @moduledoc "Atomic exchange settlement across order, warehouse, market and finance roots."
  import TijaraTides.Domain.ReadState, only: [get: 3, owned: 4]
  alias TijaraTides.Domain.{OrderBook, Notices}

  @max_lots TijaraTides.Domain.CargoRules.max_lots()
  @fill_budget 512
  @order_budget 512

  def place(state, account, cmd, id, catalogue) do
    cmd = TijaraTides.Domain.MarkdownPresetWorld.apply(state, account, cmd)
    company = get(state, "companies", account["company_id"])
    row = get(state, "warehouses", cmd["warehouse"])
    expires = cmd["expires_ms"]
    fresh = freshness_terms(cmd, nil, cmd["price"])

    cond do
      is_nil(company) or company["bankruptcy_ms"] != nil ->
        {:error, :finance_no_company}

      is_nil(row) or row["company_id"] != company["id"] ->
        {:error, :exchange_invalid}

      not OrderBook.supported?(catalogue["goods"][cmd["good"]]) ->
        {:error, :exchange_invalid}

      cmd["side"] not in ["buy", "sell"] or not is_integer(cmd["quantity"]) or
        cmd["quantity"] not in 1..@max_lots or not is_integer(cmd["price"]) or
          cmd["price"] not in 1..1_000_000_000_000 ->
        {:error, :exchange_invalid}

      expires != nil and
          (not is_integer(expires) or expires <= state.clock_ms or expires > 9_000_000_000_000_000) ->
        {:error, :exchange_invalid}

      not valid_freshness?(fresh) or
          (fresh.markdowns != nil and
             (cmd["side"] != "sell" or catalogue["goods"][cmd["good"]]["shelf_ms"] == 0)) ->
        {:error, :exchange_freshness_invalid}

      length(owned(state, "exchange_orders", "company_id", company["id"])) >= 100 or
        length(owned(state, "exchange_orders", "book_key", row["port"] <> "|" <> cmd["good"])) >=
          1000 or
          OrderBookWorld.fetch(state, id) != nil ->
        {:error, :exchange_invalid}

      true ->
        o = %OrderBook{
          id: id,
          company_id: company["id"],
          warehouse_id: row["id"],
          port: row["port"],
          good: cmd["good"],
          side: cmd["side"],
          quantity: cmd["quantity"],
          price: cmd["price"],
          priority_ms: state.clock_ms,
          priority_seq: state.revision,
          expires_ms: expires,
          min_grade: fresh.min_grade,
          min_remaining_ms: fresh.min_remaining_ms,
          markdowns: fresh.markdowns,
          price_floor: fresh.price_floor,
          initial_price:
            if(catalogue["goods"][cmd["good"]]["shelf_ms"] > 0, do: fresh.initial_price)
        }

        with {:ok, next} <- back(state, o, catalogue) do
          next =
            OrderBookWorld.accept(next, o)
            |> OrderBookWorld.synchronize(o.id)
            |> match_order(o.id, catalogue, @fill_budget)
            |> elem(0)

          {:ok, next, %{}}
        end
    end
  end

  defp freshness_terms(cmd, o, price) do
    %{
      min_grade: Map.get(cmd, "min_grade", (o && o.min_grade) || 0),
      min_remaining_ms: Map.get(cmd, "min_remaining_ms", (o && o.min_remaining_ms) || 0),
      markdowns: Map.get(cmd, "markdowns", o && o.markdowns),
      price_floor: Map.get(cmd, "price_floor", (o && o.price_floor) || 0),
      initial_price:
        if(cmd["rebase"] == true or is_nil(o) or is_nil(o.markdowns),
          do: price,
          else: o.initial_price || o.price
        )
    }
  end

  defp valid_freshness?(f),
    do:
      OrderBook.eligibility?(f.min_grade, f.min_remaining_ms) and OrderBook.schedule?(f.markdowns) and
        is_integer(f.price_floor) and f.price_floor in 0..1_000_000_000_000

  defp back(state, o, catalogue, existing_cash \\ 0) do
    c = get(state, "companies", o.company_id)
    cash = o.quantity * o.price

    if o.side == "buy" and
         (c["cash"] - c["reserved"] < cash or (c["unpaid"] > 0 and cash > existing_cash)) do
      {:error, :insufficient_cash}
    else
      with {:ok, s} <- WarehouseWorld.back_order(state, OrderBook.claim(o), catalogue) do
        {:ok, if(o.side == "buy", do: reserve_cash(s, o.company_id, cash), else: s)}
      end
    end
  end

  defp reserve_cash(state, company, n),
    do:
      CompanyFinanceWorld.post(state, company, "exchange_reservation", [
        {"cash_available", -n},
        {"cash_reserved", n}
      ])

  defp unback(state, o) do
    state = WarehouseWorld.release_trade(state, OrderBook.claim(o))
    if o.side == "buy", do: reserve_cash(state, o.company_id, -o.quantity * o.price), else: state
  end

  def cancel(state, account, id) do
    case OrderBookWorld.fetch(state, id) do
      %OrderBook{company_id: owner} = o ->
        if owner == account["company_id"],
          do:
            {:ok,
             state
             |> unback(o)
             |> OrderBookWorld.cancel(id)
             |> TijaraTides.Domain.Services.LinkedOrders.order_cancelled(id), %{}},
          else: {:error, :exchange_invalid}

      nil ->
        {:error, :exchange_invalid}
    end
  end

  def amend(state, account, cmd, catalogue) do
    cmd = TijaraTides.Domain.MarkdownPresetWorld.apply(state, account, cmd)
    o = OrderBookWorld.fetch(state, cmd["order"])
    n = cmd["quantity"]
    price = cmd["price"]
    expiry = Map.get(cmd, "expires_ms", o && o.expires_ms)
    fresh = freshness_terms(cmd, o, price)

    cond do
      is_nil(o) or o.company_id != account["company_id"] ->
        {:error, :exchange_invalid}

      String.starts_with?(o.id, "linked:") && account["linked_operation"] != true ->
        {:error, :linked_order_managed}

      not is_integer(n) or n not in 1..@max_lots or not is_integer(price) or
          price not in 1..1_000_000_000_000 ->
        {:error, :exchange_invalid}

      expiry != nil and
          (not is_integer(expiry) or expiry <= state.clock_ms or expiry > 9_000_000_000_000_000) ->
        {:error, :exchange_invalid}

      not valid_freshness?(fresh) or
          (fresh.markdowns != nil and
             (o.side != "sell" or catalogue["goods"][o.good]["shelf_ms"] == 0)) ->
        {:error, :exchange_freshness_invalid}

      get(state, "companies", o.company_id)["bankruptcy_ms"] != nil ->
        {:error, :finance_no_company}

      true ->
        reset =
          n > o.quantity or price != o.price or
            Enum.any?(fresh, fn {key, value} ->
              key != :initial_price and Map.fetch!(o, key) != value
            end) or (cmd["rebase"] == true and o.initial_price != fresh.initial_price)

        updated = OrderBookWorld.fetch(OrderBookWorld.amend(state, o.id, n, price, expiry), o.id)
        updated = struct!(updated, fresh)

        updated =
          if reset,
            do: %{updated | priority_ms: state.clock_ms, priority_seq: state.revision},
            else: updated

        with {:ok, next} <- back(unback(state, o), updated, catalogue, o.quantity * o.price) do
          next =
            next
            |> OrderBookWorld.amend(o.id, n, price, expiry)
            |> OrderBookWorld.set_terms(o.id, fresh, reset)

          {:ok, match_order(next, o.id, catalogue, @fill_budget) |> elem(0), %{}}
        end
    end
  end

  def reconcile(state), do: sweep(state, OrderBookWorld.orders(state))

  @doc "Post-command sweep: only the acting company's orders can have lost their backing."
  def reconcile(state, nil), do: state

  def reconcile(state, company_id),
    do:
      sweep(
        state,
        OrderBookWorld.company_orders(state, company_id)
      )

  defp sweep(state, orders) do
    Enum.reduce(orders, state, fn o, s ->
      company = get(s, "companies", o.company_id)

      available =
        if o.side == "sell" and map_size(o.portions) > 0,
          do:
            Enum.sum(Enum.map(WarehouseWorld.order_cargo(s, OrderBook.claim(o)), & &1.quantity)),
          else: o.quantity

      s =
        if available > 0 and available < o.quantity and
             (o.expires_ms == nil or o.expires_ms > s.clock_ms),
           do: OrderBookWorld.amend(s, o.id, available, o.price, o.expires_ms),
           else: s

      o = OrderBookWorld.fetch(s, o.id)
      s = if available > 0, do: OrderBookWorld.synchronize(s, o.id), else: s
      o = OrderBookWorld.fetch(s, o.id)

      if available == 0 or company["bankruptcy_ms"] != nil or
           (o.expires_ms != nil and o.expires_ms <= s.clock_ms) or
           not WarehouseWorld.order_backed?(s, OrderBook.claim(o)) do
        s
        |> unback(o)
        |> OrderBookWorld.cancel(o.id)
        |> TijaraTides.Domain.Services.LinkedOrders.order_cancelled(o.id)
        |> Notices.notice(
          company["account_id"],
          "exchange:" <> o.id,
          {"exchange.cancelled", %{"port" => o.port}}
        )
      else
        s
      end
    end)
  end

  @doc "Matches a shared fill and order-visit budget; unfinished work resumes next tick."
  def advance(state, catalogue, limits \\ []) do
    fills = Keyword.get(limits, :fills, @fill_budget)
    visits = Keyword.get(limits, :orders, @order_budget)
    true = is_integer(fills) and fills > 0 and is_integer(visits) and visits > 0
    state = reconcile(state)
    orders = Enum.sort_by(OrderBookWorld.orders(state), &OrderBook.priority/1)
    cursor = Map.get(state, :exchange_cursor)

    {before, after_cursor} =
      Enum.split_while(orders, &(cursor != nil and OrderBook.priority(&1) <= cursor))

    # Scheduling rotates; counterpart selection still uses price/time priority.
    # Keep the priority tuple rather than a row ID so removal of that row is safe.
    {state, _, _} =
      Enum.reduce_while(after_cursor ++ before, {state, fills, visits}, fn
        _order, {_, 0, _} = acc ->
          {:halt, acc}

        _order, {_, _, 0} = acc ->
          {:halt, acc}

        order, {state, remaining, visits} ->
          {state, remaining} = match_order(state, order.id, catalogue, remaining)
          state = Map.put(state, :exchange_cursor, OrderBook.priority(order))
          {:cont, {state, remaining, visits - 1}}
      end)

    if orders == [], do: Map.delete(state, :exchange_cursor), else: state
  end

  defp match_order(state, _id, _catalogue, 0), do: {state, 0}

  defp match_order(state, id, catalogue, budget) do
    case OrderBookWorld.fetch(state, id) do
      nil ->
        {state, budget}

      o ->
        options =
          OrderBook.quotes(o)
          |> Enum.map(fn offered ->
            peer =
              OrderBookWorld.counterparts(state, offered)
              |> Enum.find(
                &(WarehouseWorld.exchange_ready?(state, OrderBook.claim(&1)) &&
                    TijaraTides.Domain.Services.LinkedOrders.fill_allowed?(state, &1) &&
                    compatible_quantity(state, offered, &1) > 0)
              )

            {offered, peer, npc_offer(state, offered, catalogue)}
          end)

        {o, peer, npc} =
          Enum.find(options, fn {_, peer, npc} -> peer != nil or npc != nil end) || hd(options)

        use_npc =
          npc &&
            (is_nil(peer) or
               if(o.side == "buy", do: npc.price <= peer.price, else: npc.price >= peer.price))

        cond do
          not WarehouseWorld.order_backed?(state, OrderBook.claim(o)) or
              not TijaraTides.Domain.Services.LinkedOrders.fill_allowed?(state, o) ->
            {state, budget}

          use_npc ->
            n = min(o.quantity, npc.quantity)

            settle_npc(state, o, n, npc.price, catalogue)
            |> match_order(id, catalogue, budget - 1)

          peer != nil ->
            n = min(min(o.quantity, peer.quantity), compatible_quantity(state, o, peer))
            {buy, sell} = if o.side == "buy", do: {o, peer}, else: {peer, o}

            settle_pair(
              state,
              buy,
              sell,
              n,
              if(OrderBook.priority(o) < OrderBook.priority(peer), do: o.price, else: peer.price),
              catalogue
            )
            |> match_order(id, catalogue, budget - 1)

          true ->
            {state, budget}
        end
    end
  end

  defp policy(state, o),
    do: %{
      min_grade: o.min_grade,
      min_remaining_ms: o.min_remaining_ms,
      receiving_bps: WarehouseWorld.receiving_bps(state, o.warehouse_id)
    }

  defp compatible_quantity(state, first, second) do
    {buy, sell} = if first.side == "buy", do: {first, second}, else: {second, first}

    WarehouseWorld.order_cargo(state, OrderBook.claim(sell))
    |> Enum.filter(
      &((sell.lot_ids == nil or &1.lot_id in sell.lot_ids) and
          OrderBook.eligible?(&1, state.clock_ms, policy(state, buy)))
    )
    |> Enum.map(& &1.quantity)
    |> Enum.sum()
  end

  defp npc_offer(state, o, catalogue) do
    q = PortCargoMarketWorld.quote(state, catalogue, o.port, o.good)

    if q && q["manual"] do
      {price, available} =
        if o.side == "buy",
          do:
            {q["ask"],
             if(catalogue["goods"][o.good]["shelf_ms"] > 0,
               do:
                 Enum.sum(
                   for b <- q["freshness_batches"],
                       OrderBook.eligible?(
                         TijaraTides.Domain.PortCargoMarket.Rows.decode_batch(b),
                         state.clock_ms,
                         policy(state, o)
                       ),
                       do: b["quantity"]
                 ),
               else: q["stock"]
             )},
          else: {q["bid"], min(q["demand"], div(q["buyer_budget"], max(1, q["bid"])))}

      raw = if o.side == "buy", do: q["stock"], else: q["demand"]

      # The adapter quote changes at each 25-lot depth boundary; never fill beyond it at the old price.
      level = rem(max(0, raw), 25)

      if available > 0 and price > 0 and
           if(o.side == "buy", do: price <= o.price, else: price >= o.price),
         do: %{price: price, quantity: min(available, if(level == 0, do: 25, else: level))}
    end
  end

  defp settle_pair(state, buy, sell, n, price, catalogue) do
    {state, cargo} = WarehouseWorld.exchange_out(state, OrderBook.claim(sell), n)
    cost = Enum.sum(for b <- cargo, do: b.quantity * b.unit_cost)
    acquired = Enum.map(cargo, &CargoRows.encode(%{&1 | unit_cost: price}))

    state
    |> WarehouseWorld.exchange_in(OrderBook.claim(buy), acquired, n)
    |> buyer_cash(buy, n, price)
    |> TijaraTides.Domain.Services.LinkedOrders.record_fill(buy, n, catalogue)
    |> seller_cash(sell, n, price, cost)
    |> OrderBookWorld.fill(buy, n)
    |> OrderBookWorld.fill(sell, n)
    |> traded(buy, n, price)
    |> reconcile(sell.company_id)
    |> TijaraTides.Domain.Services.WarehouseLiquidation.refresh(sell.warehouse_id, catalogue)
  end

  defp settle_npc(state, o, n, price, catalogue) do
    state =
      if o.side == "buy" do
        {s, cargo} =
          PortCargoMarketWorld.release_stock(
            state,
            o.port,
            o.good,
            n,
            price,
            catalogue["goods"][o.good],
            0,
            policy(state, o)
          )

        s
        |> WarehouseWorld.exchange_in(OrderBook.claim(o), cargo, n)
        |> buyer_cash(o, n, price)
        |> TijaraTides.Domain.Services.LinkedOrders.record_fill(o, n, catalogue)
      else
        {s, cargo} = WarehouseWorld.exchange_out(state, OrderBook.claim(o), n)
        cost = Enum.sum(for b <- cargo, do: b.quantity * b.unit_cost)

        s
        |> PortCargoMarketWorld.accept_cargo(o.port, o.good, n, price, cargo)
        |> seller_cash(o, n, price, cost)
      end

    state
    |> OrderBookWorld.fill(o, n)
    |> traded(o, n, price)
    |> reconcile(o.company_id)
    |> TijaraTides.Domain.Services.WarehouseLiquidation.refresh(o.warehouse_id, catalogue)
  end

  @doc "Receiver fills valid local buy orders at their existing limit, in price/time order."
  def liquidate_stock(state, warehouse, good, catalogue) do
    alias TijaraTides.Domain.Services.WarehouseLiquidation, as: Liquidation
    w = WarehouseWorld.fetch(state, warehouse)

    if OrderBook.supported?(catalogue["goods"][good]) do
      OrderBookWorld.orders(state)
      |> Enum.filter(
        &(&1.side == "buy" and &1.port == w.port and &1.good == good and
            &1.company_id != w.company_id)
      )
      |> Enum.sort_by(&{-&1.price, OrderBook.priority(&1)})
      |> Enum.reduce_while(state, fn buy, s ->
        free =
          TijaraTides.Domain.Warehouse.unreserved_cargo(
            WarehouseWorld.fetch(s, warehouse),
            good,
            s.clock_ms
          )

        eligible = Enum.filter(free, &OrderBook.eligible?(&1, s.clock_ms, policy(s, buy)))
        n = min(buy.quantity, Enum.sum(Enum.map(eligible, & &1.quantity)))

        cond do
          free == [] ->
            {:halt, s}

          n == 0 ->
            {:cont, s}

          get(s, "companies", buy.company_id)["bankruptcy_ms"] != nil or
            (buy.expires_ms != nil and buy.expires_ms <= s.clock_ms) or
            not WarehouseWorld.exchange_ready?(s, OrderBook.claim(buy)) or
              not TijaraTides.Domain.Services.LinkedOrders.fill_allowed?(s, buy) ->
            {:cont, s}

          true ->
            {s, cargo} =
              Liquidation.take(s, warehouse, good, n, catalogue, Enum.map(eligible, & &1.lot_id))

            acquired = Enum.map(cargo, &CargoRows.encode(%{&1 | unit_cost: buy.price}))

            s =
              s
              |> WarehouseWorld.exchange_in(OrderBook.claim(buy), acquired, n)
              |> buyer_cash(buy, n, buy.price)
              |> TijaraTides.Domain.Services.LinkedOrders.record_fill(buy, n, catalogue)
              |> OrderBookWorld.fill(buy, n)
              |> traded(buy, n, buy.price)
              |> Liquidation.record_sale(warehouse, cargo, n * buy.price)

            {:cont, s}
        end
      end)
    else
      state
    end
  end

  defp buyer_cash(s, o, n, price),
    do:
      CompanyFinanceWorld.post(s, o.company_id, "exchange_purchase", [
        {"cash_reserved", -n * o.price},
        {"cash_available", n * (o.price - price)},
        {"inventory", n * price}
      ])

  defp seller_cash(s, o, n, price, cost),
    do:
      CompanyFinanceWorld.post(s, o.company_id, "exchange_sale", [
        {"inventory", -cost},
        {"cost_of_goods", cost},
        {"sales_revenue", -n * price},
        {"cash_available", n * price}
      ])

  defp traded(s, o, n, price),
    do:
      OrderBookWorld.record_trade(
        s,
        o.port,
        o.good,
        n,
        price,
        "#{o.id}:#{s.revision}:#{o.quantity}"
      )
end
