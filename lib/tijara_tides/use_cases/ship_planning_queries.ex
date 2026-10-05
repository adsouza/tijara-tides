defmodule TijaraTides.UseCases.ShipPlanningQueries do
  @moduledoc "Route and visit editor preparation, including draft defaults; never authorizes a command."
  alias TijaraTides.Domain.{
    CargoRules,
    Fleet,
    Ship,
    Warehouse,
    WarehouseWorld,
    OrderBook,
    Trading
  }

  alias TijaraTides.UseCases.{MarketQueries, WarehouseStorage}
  import TijaraTides.Domain.CargoRules, only: [compatible_cargo?: 2]

  import TijaraTides.UseCases.MarketQueries,
    only: [cargo_aboard: 2, purchase_total: 4]

  def departure_wait_orders(orders, ship, %{
        "port" => port,
        "departure_wait" => "Waiting for cargo orders to be filled or cancelled"
      }) do
    orders
    |> Enum.filter(
      &(&1["ship_id"] == ship["id"] and &1["port"] == port and
          &1["status"] in ["planned", "waiting"])
    )
    |> Enum.sort_by(& &1["id"])
  end

  def departure_wait_orders(_orders, _ship, _plan), do: []

  def route_editor(private, ship, catalogue, clock \\ 0) do
    route = Map.get(private["ship_routes"] || %{}, ship["id"])

    stops =
      (private["route_stops"] || %{})
      |> Map.values()
      |> Enum.filter(&(&1["ship_id"] == ship["id"]))
      |> Enum.sort_by(& &1["position"])

    rules =
      (private["route_rules"] || %{})
      |> Map.values()
      |> Enum.filter(&(&1["ship_id"] == ship["id"]))
      |> Enum.sort_by(&{&1["side"], &1["id"]})
      |> Enum.group_by(& &1["stop_id"])

    goods =
      catalogue["goods"]
      |> Enum.filter(fn {_, good} ->
        good["manual"] == true and CargoRules.compatible_class?(ship, good)
      end)
      |> Enum.sort_by(fn {_, good} -> good["name"] end)

    orders =
      (private["ship_instructions"] || %{})
      |> Map.values()
      |> Enum.filter(&(&1["ship_id"] == ship["id"] and String.starts_with?(&1["id"], "route:")))
      |> Enum.sort_by(&{&1["side"], &1["id"]})

    plan =
      (private["visit_plans"] || %{}) |> Map.values() |> Enum.find(&(&1["ship_id"] == ship["id"]))

    last_timeout =
      (private["notices"] || [])
      |> Enum.filter(
        &(&1["code"] == "route.wait_expired" and
            get_in(&1, ["arguments", "ship_id"]) == ship["id"])
      )
      |> Enum.max_by(& &1["clock_ms"], fn -> nil end)

    stop_goods =
      Map.new(stops, fn stop ->
        choices =
          Map.new(["buy", "sell"], fn side ->
            role = if side == "buy", do: "exp", else: "imp"

            {side,
             Enum.filter(goods, fn {id, _} ->
               String.contains?(catalogue["ports"][stop["port"]]["roles"][id] || "", role)
             end)}
          end)

        {stop["id"], choices}
      end)

    %{
      route: route,
      stops: stops,
      # The add-stop command accepts exactly these ports, and refuses any stop while
      # next-port instructions exist and no route does.
      stop_ports:
        TijaraTides.Domain.ShipWorld.route_stop_ports(
          catalogue,
          Enum.map(stops, & &1["port"]),
          route && route["status"]
        ),
      instructions_block:
        is_nil(route) and
          TijaraTides.Domain.ShipWorld.instructions_block_route?(
            Map.values(private["visit_plans"] || %{}),
            Map.values(private["ship_instructions"] || %{}),
            ship["id"]
          ),
      rules: rules,
      goods: goods,
      stop_goods: stop_goods,
      orders: orders,
      plan: plan,
      link_warehouses:
        Map.new(stops, fn stop ->
          {stop["id"],
           Map.new(goods, fn {good, item} ->
             choices =
               if OrderBook.supported?(item),
                 do:
                   (private["warehouses"] || %{})
                   |> Enum.filter(fn {_, row} ->
                     Warehouse.receiving_allowed?(
                       WarehouseWorld.snapshot(row),
                       ship["company_id"],
                       stop["port"],
                       item,
                       clock
                     )
                   end)
                   |> Enum.sort_by(&elem(&1, 0)),
                 else: []

             {good, choices}
           end)}
        end),
      links: private["remote_links"] || %{},
      exchange_orders: private["exchange_orders"] || %{},
      budgets: private["visit_budgets"] || %{},
      funding_request: get_in(private, ["departure_requests", ship["id"]]),
      last_timeout: last_timeout
    }
  end

  def instruction_editor(
        definitions,
        ship,
        draft,
        markets \\ %{},
        port \\ nil,
        company \\ nil,
        view \\ nil
      ) do
    draft =
      if draft["visit_port"] && draft["visit_port"] != port,
        do: Map.drop(draft, ["quantity", "limit"]),
        else: draft

    side = if draft["side"] == "buy", do: "buy", else: "sell"
    projected = ship |> Map.put("port", port || ship["port"]) |> Map.put("status", "docked")

    view =
      if view && port, do: visit_projection(view, ship, port, definitions.catalogue), else: view

    company = if view, do: view.private["company"], else: company
    minimum = integer(draft["freshness_minutes"]) * 60_000
    clock = if view, do: view.public["clock_ms"], else: 0

    projected =
      Map.update!(projected, "cargo", fn cargo ->
        Enum.filter(cargo, &(is_nil(&1["expires_ms"]) or &1["expires_ms"] > clock))
      end)

    warehouses =
      if view, do: Map.values(WarehouseStorage.snapshots(view.private, clock)), else: []

    sources =
      Map.new(definitions.catalogue["goods"], fn {good, _item} ->
        {good,
         Warehouse.collection_source(
           warehouses,
           projected,
           good,
           clock,
           minimum,
           definitions.catalogue
         )}
      end)

    goods =
      definitions.catalogue["goods"]
      |> Enum.sort_by(fn {good, item} -> item["name"] || good end)
      |> Enum.filter(fn {good, item} ->
        quote = if port, do: markets[port <> "|" <> good]

        item["manual"] and compatible_cargo?(ship, item) and
          (side != "buy" or is_nil(port) or
             sources[good] != nil or
             (not is_nil(quote) and quote["manual"] == true and quote["stock"] > 0)) and
          (side != "sell" or
             (cargo_aboard(projected, good) > 0 and
                (is_nil(port) or
                   (not is_nil(quote) and quote["manual"] == true and
                      is_number(quote["demand"]) and quote["demand"] > 0))))
      end)

    good =
      if List.keymember?(goods, draft["good"], 0),
        do: draft["good"],
        else:
          (case goods do
             [{id, _} | _] -> id
             [] -> nil
           end)

    quote = if port && good, do: markets[port <> "|" <> good]
    item = definitions.catalogue["goods"][good]

    maximum =
      cond do
        side == "sell" ->
          Enum.min([
            CargoRules.max_lots(),
            cargo_aboard(projected, good),
            if(quote, do: Trading.sale_capacity(quote), else: CargoRules.max_lots())
          ])

        company && item && view ->
          case instruction_onwards(view.private, ship["id"], port) do
            [onward] ->
              options = %{
                cap: if(draft["budget"], do: integer(draft["budget"]) * 100),
                minimum: minimum,
                limit: quote && quote["ask"]
              }

              if source = sources[good],
                do:
                  collection_offer(
                    view,
                    projected,
                    onward,
                    source,
                    item,
                    definitions.catalogue,
                    options
                  ),
                else:
                  MarketQueries.purchase_offer(
                    view,
                    projected,
                    onward,
                    good,
                    definitions.catalogue,
                    options
                  )

            _ ->
              0
          end

        port ->
          0

        true ->
          10_000
      end

    default_quantity = if side == "sell" or company, do: maximum, else: 1
    price = if quote, do: quote[if(side == "sell", do: "bid", else: "ask")], else: 0
    default_limit = Decimal.new(price || 0) |> Decimal.div(100) |> Decimal.to_string(:normal)

    quantity =
      case Integer.parse(to_string(draft["quantity"] || default_quantity)) do
        {n, ""} -> n
        _ -> 1
      end

    quantity = if(maximum < 1, do: 0, else: min(maximum, max(1, quantity)))

    budget =
      if side == "buy" && item && (quote || sources[good]),
        do:
          div(
            instruction_cost(quote, sources[good], ship, item, quantity, definitions.catalogue) +
              99,
            100
          ),
        else: 10_000

    %{
      goods: goods,
      good: good,
      side: side,
      maximum: maximum,
      limit: draft["limit"] || default_limit,
      budget: draft["budget"] || to_string(max(1, budget)),
      quantity: quantity
    }
  end

  # Account for the known inbound journey without assuming market replenishment,
  # sales proceeds, or other future income. Existing voyage fuel is already reserved.
  defp visit_projection(view, %{"port" => port, "status" => status}, port, _catalogue)
       when status != "sailing", do: view

  defp visit_projection(view, ship, port, catalogue) do
    clock = view.public["clock_ms"]
    fleet = Map.values(view.private["ships"])
    company = view.private["company"]

    {duration, cost, released} =
      if ship["status"] == "sailing" do
        duration = max(0, ship["arrive_ms"] - clock)
        fuel = ship["fuel_total"] - ship["fuel_burned"]

        upkeep =
          Enum.sum(
            for s <- fleet do
              sailing = Fleet.moving_time(s, clock, clock + duration)

              Ship.crew_estimate(s, sailing, duration - sailing) +
                Fleet.maintenance_estimate(s, clock, clock + duration)
            end
          )

        {duration, fuel + upkeep, fuel}
      else
        handling =
          if ship["status"] in ["loading", "unloading"],
            do: max(0, ship["arrive_ms"] - clock),
            else: 0

        voyage =
          Trading.voyage_requirement(
            Map.put(ship, "status", "docked"),
            handling,
            port,
            fleet,
            clock,
            catalogue
          )

        if voyage,
          do: {handling + voyage["duration_ms"], voyage["required"], 0},
          else: {0, company["cash"] - company["reserved"], 0}
      end

    view
    |> put_in([:public, "clock_ms"], clock + duration)
    |> put_in([:private, "company"], %{
      company
      | "cash" => company["cash"] - cost,
        "reserved" => company["reserved"] - released
    })
  end

  defp instruction_cost(quote, nil, ship, item, n, _catalogue),
    do: purchase_total(quote, ship, item, n)

  defp instruction_cost(_quote, source, ship, item, n, catalogue),
    do:
      n * TijaraTides.Domain.PortCargoMarket.handling_rate(catalogue["ports"][source.port]) +
        WarehouseWorld.cleaning_cost(ship, item)

  defp collection_offer(view, ship, onward, source, item, catalogue, options) do
    company = view.private["company"]
    clock = view.public["clock_ms"]
    cash = company["cash"] - company["reserved"]
    cleaning = WarehouseWorld.cleaning_cost(ship, item)
    handling = TijaraTides.Domain.PortCargoMarket.handling_rate(catalogue["ports"][source.port])

    if company["unpaid"] == 0 && is_nil(company["bankruptcy_ms"]) &&
         clock >= source.protected_ms && Warehouse.compatible?(source, item) &&
         CargoRules.valid_remaining?(options.minimum) do
      capacity =
        Warehouse.transfer_limits(source, "collect", item, %{
          now: clock,
          ship_id: ship["id"],
          minimum: options.minimum,
          hold_rate: CargoRules.hold_rate(ship, catalogue),
          hold_lots: WarehouseWorld.hold_lots(ship, item, catalogue),
          cash: cash,
          cleaning: cleaning,
          handling: handling
        })
        |> Map.values()
        |> Enum.min()
        |> min(CargoRules.max_lots())

      MarketQueries.largest_trade(0, capacity, fn n ->
        loaded = Map.update!(ship, "cargo", &(&1 ++ [%{"good" => item["id"], "quantity" => n}]))

        loading =
          CargoRules.loading_ms(
            CargoRules.handling_ms(n, source.port, item["id"], catalogue),
            cleaning
          )

        voyage = Fleet.voyage_quote(loaded, onward, catalogue, clock + loading, clock)
        total = n * handling + cleaning

        voyage && (is_nil(options.cap) || total <= options.cap) &&
          cash - total >= voyage["fuel"] + voyage["canal_fees"]
      end)
    else
      0
    end
  end

  defp integer(nil), do: 0
  defp integer(""), do: 0

  defp integer(value) when is_integer(value), do: value

  defp integer(value) when is_binary(value) and byte_size(value) <= 12 do
    case Integer.parse(value) do
      {n, ""} -> n
      _ -> -1
    end
  end

  defp integer(_value), do: -1

  def instruction_visits(private, ship_id) do
    from_orders =
      private["ship_instructions"]
      |> Map.values()
      |> Enum.filter(
        &(&1["ship_id"] == ship_id and &1["side"] == "buy" and
            &1["status"] in ["planned", "waiting"])
      )
      |> Enum.group_by(& &1["port"], & &1["onward"])
      |> Map.new(fn {port, onwards} -> {port, Enum.sort(Enum.uniq(onwards))} end)

    Map.get(private, "visit_plans", %{})
    |> Map.values()
    |> Enum.filter(&(&1["ship_id"] == ship_id))
    |> Enum.reduce(from_orders, fn plan, visits ->
      Map.update(
        visits,
        plan["port"],
        [plan["onward"]],
        &Enum.sort(Enum.uniq([plan["onward"] | &1]))
      )
    end)
  end

  def instruction_onwards(private, ship_id, port),
    do: Map.get(instruction_visits(private, ship_id), port, [])
end
