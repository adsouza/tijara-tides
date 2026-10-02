defmodule TijaraTides.Domain.OrderBookWorld do
  @moduledoc "Standing standardized-cargo orders, price-time priority and bounded public trade history."
  import TijaraTides.Domain.State

  alias TijaraTides.Domain.OrderBook
  alias TijaraTides.Domain.OrderBook.Rows

  @doc "Retain terms and priority when won cargo acquires replacement storage in the same space."
  def relocate_storage(state, old, new) do
    previous = get(state, "warehouses", old)
    replacement = get(state, "warehouses", new)

    unless previous && replacement && previous["company_id"] == replacement["company_id"] &&
             previous["port"] == replacement["port"] &&
             previous["storage"] == replacement["storage"] &&
             previous["space_group"] == replacement["space_group"],
           do:
             raise(ArgumentError, "Replacement storage must retain ownership and physical space")

    Enum.reduce(orders(state), state, fn order, s ->
      if order.warehouse_id == old, do: store(s, %{order | warehouse_id: new}), else: s
    end)
  end

  @doc "Refresh separately priced physical-lot portions without changing unchanged priorities."
  def synchronize(state, id, reset \\ false) do
    case fetch(state, id) do
      %{side: "sell"} = o ->
        batches = TijaraTides.Domain.WarehouseWorld.order_cargo(state, OrderBook.claim(o))

        if Enum.any?(batches, & &1.expires_ms) do
          parents = Map.new(Map.get(state, :new_lots, []), &{&1["id"], &1["parent_lot_id"]})

          portions =
            Map.new(batches, fn b ->
              grade = OrderBook.grade(b, state.clock_ms)
              price = OrderBook.effective_price(o, grade)
              old = ancestor_portion(o.portions, b.lot_id, parents)

              same =
                old && old["grade"] == grade && old["price"] == price &&
                  old["quantity"] >= b.quantity && not reset

              {b.lot_id,
               %{
                 "lot_id" => b.lot_id,
                 "quantity" => b.quantity,
                 "grade" => grade,
                 "price" => price,
                 "expires_ms" => b.expires_ms,
                 "priority_ms" => if(same, do: old["priority_ms"], else: state.clock_ms),
                 "priority_seq" => if(same, do: old["priority_seq"], else: state.revision)
               }}
            end)

          store(state, %{
            o
            | portions: portions,
              quantity: Enum.sum(Enum.map(batches, & &1.quantity))
          })
        else
          state
        end

      _ ->
        state
    end
  end

  @doc """
  Sell portions are derived from their warehouse's cargo and claims. Any transition that
  declares a change to either re-derives the portions of that warehouse's sell orders,
  in the same transaction so split lots still trace to their parent portions.
  """
  def synchronize_changed(before, state) do
    warehouses =
      for {{kind, id}, _} <- TijaraTides.Domain.ChangeSet.since(before, state),
          kind in ["warehouses", "warehouse_reservations"],
          source <- [before, state],
          row = get_in(source, [:entities, kind, id]),
          row != nil,
          uniq: true,
          do: {row["company_id"], if(kind == "warehouses", do: id, else: row["warehouse_id"])}

    Enum.reduce(Enum.sort(warehouses), state, fn {company, warehouse}, s ->
      owned(s, "exchange_orders", "company_id", company)
      |> Enum.filter(&(&1["warehouse_id"] == warehouse and &1["side"] == "sell"))
      |> Enum.reduce(s, &synchronize(&2, &1["id"]))
    end)
  end

  defp ancestor_portion(portions, id, parents) do
    portions[id] || if(parents[id], do: ancestor_portion(portions, parents[id], parents))
  end

  def set_terms(state, id, terms, reset) do
    o = fetch!(state, id)
    o = struct!(o, terms)
    o = if reset, do: %{o | priority_ms: state.clock_ms, priority_seq: state.revision}, else: o
    store(state, o) |> synchronize(id, reset)
  end

  def orders(state), do: Enum.map(Map.values(entities(state, "exchange_orders")), &Rows.decode/1)

  def fetch(state, id) do
    case get(state, "exchange_orders", id) do
      nil -> nil
      row -> Rows.decode(row)
    end
  end

  def accept(state, %OrderBook{} = order) do
    store(
      state,
      OrderBook.accept(order, state.clock_ms, state.revision, fetch(state, order.id) != nil)
    )
  end

  def amend(state, id, quantity, price, expires_ms) do
    store(
      state,
      OrderBook.amend(
        fetch!(state, id),
        quantity,
        price,
        expires_ms,
        state.clock_ms,
        state.revision
      )
    )
  end

  def cancel(state, id) do
    fetch!(state, id)
    delete(state, "exchange_orders", id)
  end

  def fill(state, %OrderBook{} = order, quantity) do
    case OrderBook.fill(fetch!(state, order.id), order, quantity) do
      :filled -> cancel(state, order.id)
      remainder -> store(state, remainder)
    end
  end

  def company_orders(state, id),
    do: Enum.map(owned(state, "exchange_orders", "company_id", id), &Rows.decode/1)

  defp fetch!(state, id) do
    fetch(state, id) || raise ArgumentError, "Order does not exist"
  end

  defp store(state, order), do: put(state, "exchange_orders", order.id, Rows.encode(order))

  def counterparts(state, incoming) do
    owned(state, "exchange_orders", "book_key", incoming.port <> "|" <> incoming.good)
    |> Enum.map(&Rows.decode/1)
    |> Enum.flat_map(&OrderBook.quotes/1)
    |> OrderBook.counterparts(incoming)
  end

  def record_trade(state, port, good, n, price, id) do
    row = %{
      "id" => id,
      "port" => port,
      "good" => good,
      "quantity" => n,
      "price" => price,
      "clock_ms" => state.clock_ms,
      "sequence" => state.revision
    }

    state = put(state, "exchange_trades", id, row)

    owned(state, "exchange_trades", "book_key", port <> "|" <> good)
    |> Enum.sort_by(&{&1["clock_ms"], &1["sequence"], &1["id"]}, :desc)
    |> Enum.drop(20)
    |> Enum.reduce(state, &delete(&2, "exchange_trades", &1["id"]))
  end

  def public(state) do
    orders(state)
    |> Enum.flat_map(&OrderBook.quotes/1)
    |> Enum.group_by(&(&1.port <> "|" <> &1.good))
    |> Map.new(fn {key, os} ->
      levels =
        os
        |> Enum.group_by(&{&1.side, &1.price, &1.actual_grade, &1.min_grade, &1.min_remaining_ms})
        |> Enum.map(fn {{side, price, grade, minimum, life}, rows} ->
          %{
            "side" => side,
            "price" => price,
            "quantity" => Enum.sum(Enum.map(rows, & &1.quantity))
          }
          |> then(fn row ->
            if grade != nil or minimum > 0 or life > 0,
              do:
                Map.merge(row, %{
                  "grade" => grade,
                  "min_grade" => minimum,
                  "min_remaining_ms" => life
                })
                |> then(fn level ->
                  if grade != nil do
                    expiry = Enum.min(Enum.map(rows, & &1.portions[&1.portion_id]["expires_ms"]))
                    Map.put(level, "remaining_ms", max(0, expiry - state.clock_ms))
                  else
                    level
                  end
                end),
              else: row
          end)
        end)

      {key, Enum.sort_by(levels, &{&1["side"], &1["price"]})}
    end)
  end

  def recent(state),
    do:
      entities(state, "exchange_trades")
      |> Map.values()
      |> Enum.sort_by(&{&1["clock_ms"], &1["sequence"], &1["id"]}, :desc)
      |> Enum.map(&Map.drop(&1, ["id"]))
      |> Enum.group_by(&(&1["port"] <> "|" <> &1["good"]))
end
