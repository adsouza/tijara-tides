defmodule TijaraTides.UseCases.ShipPlanningQueries do
  @moduledoc "Route and visit editor preparation, including draft defaults; never authorizes a command."
  alias TijaraTides.Domain.{Fleet, CargoRules}
  import TijaraTides.Domain.CargoRules, only: [compatible_cargo?: 2]

  import TijaraTides.UseCases.MarketQueries,
    only: [cargo_aboard: 2, purchase_total: 4, largest_trade: 3]

  def route_editor(private, ship, catalogue) do
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
      rules: rules,
      goods: goods,
      stop_goods: stop_goods,
      orders: orders,
      plan: plan
    }
  end

  def instruction_editor(definitions, ship, draft, markets \\ %{}, port \\ nil, company \\ nil) do
    draft =
      if draft["visit_port"] && draft["visit_port"] != port,
        do: Map.drop(draft, ["quantity", "limit"]),
        else: draft

    side = if draft["side"] == "buy", do: "buy", else: "sell"

    goods =
      definitions.catalogue["goods"]
      |> Enum.sort_by(fn {good, item} -> item["name"] || good end)
      |> Enum.filter(fn {good, item} ->
        quote = if port, do: markets[port <> "|" <> good]

        item["manual"] and compatible_cargo?(ship, item) and
          (side != "buy" or is_nil(port) or
             (not is_nil(quote) and quote["manual"] == true and quote["stock"] > 0)) and
          (side != "sell" or
             (cargo_aboard(ship, good) > 0 and
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
          min(CargoRules.max_lots(), cargo_aboard(ship, good))

        company && quote && item ->
          class = Fleet.classes()[ship["class"]]

          capacity =
            Enum.min([
              10_000,
              quote["stock"],
              div(class["weight"], item["weight_kg"]),
              div(class["volume"], item["volume_l"])
            ])

          cash = max(0, company["cash"] - company["reserved"])

          cap =
            case Integer.parse(to_string(draft["budget"] || "")) do
              {n, ""} -> min(cash, max(0, n * 100))
              _ -> cash
            end

          largest_trade(0, capacity, fn quantity ->
            purchase_total(quote, ship, item, quantity) <= cap
          end)

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
      if side == "buy" && quote && item,
        do: div(purchase_total(quote, ship, item, quantity) + 99, 100),
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
