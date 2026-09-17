defmodule TijaraTides.Domain.MerchantWarehouseWorld do
  @moduledoc "Lease merchant storage, charge its finite market budget and account for pool occupancy."
  alias TijaraTides.Domain.{State, MerchantWarehouse, WarehouseWorld, PortCargoMarketWorld}
  @day 86_400_000

  def fetch(s, id) do
    case State.get(s, "merchant_warehouses", id) do
      nil -> nil
      row -> TijaraTides.Domain.MerchantWarehouse.Rows.decode(row)
    end
  end

  def active?(s, id, until_ms \\ nil) do
    w = fetch(s, id)

    w != nil and w.protected_ms <= s.clock_ms and
      MerchantWarehouse.covers?(w, until_ms || s.clock_ms)
  end

  def protect(s, id, until_ms) do
    w = fetch(s, id) |> MerchantWarehouse.protect(until_ms)
    State.put(s, "merchant_warehouses", id, TijaraTides.Domain.MerchantWarehouse.Rows.encode(w))
  end

  def free(s, id, stock) do
    case fetch(s, id) do
      nil ->
        0

      w ->
        if MerchantWarehouse.open?(w, s.clock_ms), do: MerchantWarehouse.free(w, stock), else: 0
    end
  end

  def advance(s, cat) do
    # Pool occupancy is carried through the reduce, so each lease still prices against
    # the leases granted before it without rescanning both warehouse tables per merchant.
    State.entities(s, "markets")
    |> Enum.filter(fn {_, m} -> m["merchant"] end)
    |> Enum.sort()
    |> Enum.reduce({s, WarehouseWorld.pools(s)}, fn {id, m}, {s, pools} ->
      begin_advance(s, pools, id, m, cat)
    end)
    |> elem(0)
  end

  defp begin_advance(s, pools, id, m, cat) do
    w = fetch(s, id)
    item = cat["goods"][m["good"]]
    pool = m["port"] <> "|" <> item["hold"]
    target = max(m["stock"], get_in(cat, ["merchants", "storage_lots"]) || 10)

    blocks =
      if w,
        do: w.blocks,
        else:
          div(
            target * item["volume_l"] + WarehouseWorld.block_litres() - 1,
            WarehouseWorld.block_litres()
          )

    used = max(0, Map.get(pools, pool, 0) - if(w, do: w.blocks, else: 0))

    daily = WarehouseWorld.quote(used, item["hold"], blocks, 1)
    needs = w == nil or w.expires_ms <= s.clock_ms + @day

    price =
      daily && daily * (3 + if(w, do: MerchantWarehouse.overdue_days(w, s.clock_ms), else: 0))

    cond do
      needs and price != nil and m["budget"] >= price ->
        next = %MerchantWarehouse{
          id: id,
          port: m["port"],
          good: m["good"],
          storage: item["hold"],
          blocks: blocks,
          capacity: div(blocks * WarehouseWorld.block_litres(), item["volume_l"]),
          protected_ms: if(w, do: w.protected_ms, else: s.clock_ms),
          expires_ms: max(s.clock_ms, if(w, do: w.expires_ms, else: s.clock_ms)) + 3 * @day
        }

        s =
          s
          |> State.put(
            "merchant_warehouses",
            id,
            TijaraTides.Domain.MerchantWarehouse.Rows.encode(next)
          )
          |> PortCargoMarketWorld.pay_storage(m["port"], m["good"], price)

        {s, Map.update(pools, pool, blocks, &(&1 + blocks - if(w, do: w.blocks, else: 0)))}

      w != nil and MerchantWarehouse.cleared?(w, s.clock_ms) ->
        s =
          s
          |> PortCargoMarketWorld.clear_merchant(m["port"], m["good"])
          |> State.delete("merchant_warehouses", id)

        {s, Map.update(pools, pool, 0, &max(0, &1 - w.blocks))}

      true ->
        {s, pools}
    end
  end
end
