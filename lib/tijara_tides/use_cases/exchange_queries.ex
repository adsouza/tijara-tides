defmodule TijaraTides.UseCases.ExchangeQueries do
  @moduledoc "Exchange books, quotes and owner-scoped order options."

  def exchange_options(definitions, view, port, selected) do
    goods =
      definitions.catalogue["goods"]
      |> Enum.filter(fn {_, item} -> TijaraTides.Domain.OrderBook.supported?(item) end)
      |> Enum.sort()

    good = if Enum.any?(goods, &(elem(&1, 0) == selected)), do: selected, else: elem(hd(goods), 0)
    item = definitions.catalogue["goods"][good]

    warehouses =
      ((view.private && view.private["warehouses"]) || %{})
      |> Map.values()
      |> Enum.filter(&(&1["port"] == port and &1["expires_ms"] > view.public["clock_ms"]))
      |> Enum.filter(
        &TijaraTides.Domain.Warehouse.compatible?(
          TijaraTides.Domain.WarehouseWorld.snapshot(&1),
          item
        )
      )
      |> Enum.sort_by(& &1["id"])

    orders =
      ((view.private && view.private["exchange_orders"]) || %{})
      |> Map.values()
      |> Enum.filter(&(&1["port"] == port))
      |> Enum.sort_by(&{&1["priority_ms"], &1["priority_seq"], &1["id"]})

    levels = get_in(view.public, ["order_books", port <> "|" <> good]) || []
    q = view.markets[port <> "|" <> good]

    npc =
      if q && q["manual"],
        do:
          for(
            {side, price, n} <- [
              {"sell", q["ask"], q["stock"]},
              {"buy", q["bid"], min(q["demand"], div(q["buyer_budget"], max(1, q["bid"])))}
            ],
            n > 0,
            do: %{
              "side" => side,
              "price" => price,
              "quantity" =>
                min(
                  n,
                  case rem(if(side == "sell", do: q["stock"], else: q["demand"]), 25) do
                    0 -> 25
                    x -> x
                  end
                ),
              "npc" => true
            }
          ),
        else: []

    levels = Enum.map(levels, &Map.put(&1, "npc", false)) ++ npc

    trades =
      (get_in(view.public, ["exchange_trades", port <> "|" <> good]) || [])
      |> Enum.sort_by(&{&1["clock_ms"], &1["sequence"], &1["id"]}, :desc)

    %{
      goods: goods,
      good: good,
      warehouses: warehouses,
      orders: orders,
      bids: Enum.filter(levels, &(&1["side"] == "buy")) |> Enum.sort_by(& &1["price"], :desc),
      asks: Enum.filter(levels, &(&1["side"] == "sell")) |> Enum.sort_by(& &1["price"]),
      trades: trades,
      quote: q
    }
  end
end
