defmodule TijaraTides.Domain.Services.Exchange do
  @moduledoc "Atomic exchange settlement across order, warehouse, market and finance roots."
  import TijaraTides.Domain.ReadState, only: [get: 3, owned: 4]
  alias TijaraTides.Domain.{OrderBook, Warehouse, CompanyFinance, PortCargoMarket, Notices}
  alias TijaraTides.Domain.Ship.CargoBatch

  @max_lots TijaraTides.Domain.CargoRules.max_lots()
  @fill_budget 512
  @order_budget 512

  def place(state, account, cmd, id, catalogue) do
    company = get(state, "companies", account["company_id"])
    row = get(state, "warehouses", cmd["warehouse"])
    expires = cmd["expires_ms"]

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

      length(owned(state, "exchange_orders", "company_id", company["id"])) >= 100 or
        length(owned(state, "exchange_orders", "book_key", row["port"] <> "|" <> cmd["good"])) >=
          1000 or
          OrderBook.fetch(state, id) != nil ->
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
          expires_ms: expires
        }

        with {:ok, next} <- back(state, o, catalogue) do
          next =
            OrderBook.accept(next, o) |> match_order(o.id, catalogue, @fill_budget) |> elem(0)

          {:ok, next, %{}}
        end
    end
  end

  defp back(state, o, catalogue, existing_cash \\ 0) do
    c = get(state, "companies", o.company_id)
    cash = o.quantity * o.price

    if o.side == "buy" and
         (c["cash"] - c["reserved"] < cash or (c["unpaid"] > 0 and cash > existing_cash)) do
      {:error, :insufficient_cash}
    else
      with {:ok, s} <- Warehouse.back_order(state, OrderBook.claim(o), catalogue) do
        {:ok, if(o.side == "buy", do: reserve_cash(s, o.company_id, cash), else: s)}
      end
    end
  end

  defp reserve_cash(state, company, n),
    do:
      CompanyFinance.post(state, company, "exchange_reservation", [
        {"cash_available", -n},
        {"cash_reserved", n}
      ])

  defp unback(state, o) do
    state = Warehouse.release_trade(state, OrderBook.claim(o))
    if o.side == "buy", do: reserve_cash(state, o.company_id, -o.quantity * o.price), else: state
  end

  def cancel(state, account, id) do
    case OrderBook.fetch(state, id) do
      %OrderBook{company_id: owner} = o ->
        if owner == account["company_id"],
          do: {:ok, state |> unback(o) |> OrderBook.remove(id), %{}},
          else: {:error, :exchange_invalid}

      nil ->
        {:error, :exchange_invalid}
    end
  end

  def amend(state, account, cmd, catalogue) do
    o = OrderBook.fetch(state, cmd["order"])
    n = cmd["quantity"]
    price = cmd["price"]
    expiry = Map.get(cmd, "expires_ms", o && o.expires_ms)

    cond do
      is_nil(o) or o.company_id != account["company_id"] ->
        {:error, :exchange_invalid}

      not is_integer(n) or n not in 1..@max_lots or not is_integer(price) or
          price not in 1..1_000_000_000_000 ->
        {:error, :exchange_invalid}

      expiry != nil and
          (not is_integer(expiry) or expiry <= state.clock_ms or expiry > 9_000_000_000_000_000) ->
        {:error, :exchange_invalid}

      get(state, "companies", o.company_id)["bankruptcy_ms"] != nil ->
        {:error, :finance_no_company}

      true ->
        reset = n > o.quantity or price != o.price

        updated = %{
          o
          | quantity: n,
            price: price,
            expires_ms: expiry,
            priority_ms: if(reset, do: state.clock_ms, else: o.priority_ms),
            priority_seq: if(reset, do: state.revision, else: o.priority_seq)
        }

        with {:ok, next} <- back(unback(state, o), updated, catalogue, o.quantity * o.price) do
          {:ok,
           next
           |> OrderBook.accept(updated)
           |> match_order(o.id, catalogue, @fill_budget)
           |> elem(0), %{}}
        end
    end
  end

  def reconcile(state), do: sweep(state, OrderBook.orders(state))

  @doc "Post-command sweep: only the acting company's orders can have lost their backing."
  def reconcile(state, nil), do: state

  def reconcile(state, company_id),
    do:
      sweep(
        state,
        Enum.map(owned(state, "exchange_orders", "company_id", company_id), &OrderBook.from_row/1)
      )

  defp sweep(state, orders) do
    Enum.reduce(orders, state, fn o, s ->
      company = get(s, "companies", o.company_id)

      if company["bankruptcy_ms"] != nil or (o.expires_ms != nil and o.expires_ms <= s.clock_ms) or
           not Warehouse.order_backed?(s, OrderBook.claim(o)) do
        s
        |> unback(o)
        |> OrderBook.remove(o.id)
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
    orders = Enum.sort_by(OrderBook.orders(state), &OrderBook.priority/1)
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
    case OrderBook.fetch(state, id) do
      nil ->
        {state, budget}

      o ->
        peer =
          OrderBook.counterparts(state, o)
          |> Enum.find(&Warehouse.exchange_ready?(state, OrderBook.claim(&1)))

        npc = npc_offer(state, o, catalogue)

        use_npc =
          npc &&
            (is_nil(peer) or
               if(o.side == "buy", do: npc.price <= peer.price, else: npc.price >= peer.price))

        cond do
          not Warehouse.order_backed?(state, OrderBook.claim(o)) ->
            {state, budget}

          use_npc ->
            n = min(o.quantity, npc.quantity)

            settle_npc(state, o, n, npc.price, catalogue)
            |> match_order(id, catalogue, budget - 1)

          peer != nil ->
            n = min(o.quantity, peer.quantity)
            {buy, sell} = if o.side == "buy", do: {o, peer}, else: {peer, o}

            settle_pair(
              state,
              buy,
              sell,
              n,
              if(OrderBook.priority(o) < OrderBook.priority(peer), do: o.price, else: peer.price)
            )
            |> match_order(id, catalogue, budget - 1)

          true ->
            {state, budget}
        end
    end
  end

  defp npc_offer(state, o, catalogue) do
    q = PortCargoMarket.quote(state, catalogue, o.port, o.good)

    if q && q["manual"] do
      {price, available} =
        if o.side == "buy",
          do: {q["ask"], q["stock"]},
          else: {q["bid"], min(q["demand"], div(q["buyer_budget"], max(1, q["bid"])))}

      raw = if o.side == "buy", do: q["stock"], else: q["demand"]

      # The adapter quote changes at each 25-lot depth boundary; never fill beyond it at the old price.
      level = rem(max(0, raw), 25)

      if available > 0 and price > 0 and
           if(o.side == "buy", do: price <= o.price, else: price >= o.price),
         do: %{price: price, quantity: min(available, if(level == 0, do: 25, else: level))}
    end
  end

  defp settle_pair(state, buy, sell, n, price) do
    {state, cargo} = Warehouse.exchange_out(state, OrderBook.claim(sell), n)
    cost = Enum.sum(for b <- cargo, do: b.quantity * b.unit_cost)
    acquired = Enum.map(cargo, &CargoBatch.to_row(%{&1 | unit_cost: price}))

    state
    |> Warehouse.exchange_in(OrderBook.claim(buy), acquired, n)
    |> buyer_cash(buy, n, price)
    |> seller_cash(sell, n, price, cost)
    |> OrderBook.fill(buy, n)
    |> OrderBook.fill(sell, n)
    |> traded(buy, n, price)
  end

  defp settle_npc(state, o, n, price, catalogue) do
    state =
      if o.side == "buy" do
        {s, cargo} =
          PortCargoMarket.release_stock(
            state,
            o.port,
            o.good,
            n,
            price,
            catalogue["goods"][o.good]
          )

        s |> Warehouse.exchange_in(OrderBook.claim(o), cargo, n) |> buyer_cash(o, n, price)
      else
        {s, cargo} = Warehouse.exchange_out(state, OrderBook.claim(o), n)
        cost = Enum.sum(for b <- cargo, do: b.quantity * b.unit_cost)

        s
        |> PortCargoMarket.accept_cargo(o.port, o.good, n, price)
        |> seller_cash(o, n, price, cost)
      end

    state |> OrderBook.fill(o, n) |> traded(o, n, price)
  end

  defp buyer_cash(s, o, n, price),
    do:
      CompanyFinance.post(s, o.company_id, "exchange_purchase", [
        {"cash_reserved", -n * o.price},
        {"cash_available", n * (o.price - price)},
        {"inventory", n * price}
      ])

  defp seller_cash(s, o, n, price, cost),
    do:
      CompanyFinance.post(s, o.company_id, "exchange_sale", [
        {"inventory", -cost},
        {"cost_of_goods", cost},
        {"sales_revenue", -n * price},
        {"cash_available", n * price}
      ])

  defp traded(s, o, n, price),
    do: OrderBook.record_trade(s, o.port, o.good, n, price, "#{o.id}:#{s.revision}:#{o.quantity}")
end
