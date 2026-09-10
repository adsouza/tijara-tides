defmodule TijaraTides.UseCases.GameQueries do
  defdelegate compatible_cargo?(ship, item), to: TijaraTides.Domain.CargoRules

  @moduledoc "Pure read-side planning projections. Reads never mutate domain state."
  alias TijaraTides.Domain.{Fleet, Trading, CargoRules, Visibility}

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

  def ship_sale_value(ship, clock), do: Fleet.sale_value(ship, clock)

  def preview(game, catalogue, authenticated, id, destination) do
    with true <- is_binary(destination),
         {:ok, account} <- authenticated,
         %{"company_id" => owner, "status" => "docked"} = ship <-
           TijaraTides.Domain.ReadState.get(game, "ships", id),
         true <- owner == account["company_id"] do
      case Fleet.voyage_quote(ship, destination, catalogue) do
        nil ->
          nil

        quote ->
          Map.put(
            quote,
            "freshness",
            CargoRules.voyage_freshness(ship, game.clock_ms, quote["duration_ms"])
          )
      end
    else
      _ -> nil
    end
  end

  def snapshot(game, catalogue, projection, account) do
    private =
      case account do
        {:ok, account} ->
          private = Visibility.private(game, account)

          compatible =
            Map.new(private["ships"], fn {id, ship} ->
              {id,
               for(
                 {good, item} <- catalogue["goods"],
                 CargoRules.compatible_cargo?(ship, item),
                 do: good
               )}
            end)

          underway =
            Map.new(private["ships"], fn {id, ship} ->
              estimates =
                if ship["status"] == "sailing",
                  do:
                    CargoRules.voyage_freshness(
                      ship,
                      game.clock_ms,
                      max(0, ship["arrive_ms"] - game.clock_ms)
                    ),
                  else: []

              {id, estimates}
            end)

          private
          |> Map.put("compatible_cargo", compatible)
          |> Map.put("voyage_freshness", underway)

        _ ->
          nil
      end

    %{status: :ready, public: projection.public, private: private, markets: projection.markets}
  end

  def destination_options(definitions, view, ship, destination) do
    if ship && ship["status"] == "docked" && ship["port"] != destination do
      space = Fleet.capacity(ship, definitions.catalogue)
      class = definitions.classes[ship["class"]]
      fleet = Map.values(view.private["ships"])

      for {good, item} <-
            Enum.sort_by(definitions.catalogue["goods"], fn {good, _} ->
              definitions.catalogue["goods"][good]["name"] || good
            end),
          source = view.markets[ship["port"] <> "|" <> good],
          source["manual"] && source["stock"] > 0 && CargoRules.compatible_cargo?(ship, item) do
        buyer = view.markets[destination <> "|" <> good]
        demand = if buyer["manual"], do: buyer["demand"], else: 0

        lots =
          max(
            0,
            Enum.min([
              source["stock"],
              demand,
              div(class["weight"] - space.weight, item["weight_kg"]),
              div(class["volume"] - space.volume, item["volume_l"])
            ])
          )

        voyage =
          if lots > 0,
            do:
              purchase_voyage(
                ship,
                item,
                lots,
                destination,
                view.private["ships"],
                view.public["clock_ms"],
                definitions.catalogue
              )

        profit =
          if voyage do
            unloading_upkeep =
              Enum.sum(
                Enum.map(fleet, fn s ->
                  div(
                    CargoRules.handling_ms(lots) * definitions.classes[s["class"]]["crew"] * 2 +
                      119_999,
                    120_000
                  )
                end)
              )

            lots * (buyer["bid"] - buyer["handling_fee"]) -
              Trading.purchase_total(source, ship, item, lots) - voyage["required"] -
              unloading_upkeep
          end

        %{
          good: good,
          item: item,
          source: source,
          buyer: buyer,
          demand: demand,
          lots: lots,
          profit: profit
        }
      end
    else
      []
    end
  end

  def purchase_total(quote, ship, item, quantity),
    do: Trading.purchase_total(quote, ship, item, quantity)

  def trade_limits(view, ship, destination, catalogue) do
    if ship && ship["status"] == "docked" && view.private do
      space = Fleet.capacity(ship, catalogue)
      class = Fleet.classes()[ship["class"]]
      company = view.private["company"]
      cash = company["cash"] - company["reserved"]

      Map.new(
        for {good, item} <- catalogue["goods"], side <- ["buy", "sell"] do
          q = view.markets[ship["port"] <> "|" <> good]

          limit =
            cond do
              !q["manual"] ->
                0

              side == "sell" ->
                aboard =
                  Enum.sum(
                    for batch <- ship["cargo"], batch["good"] == good, do: batch["quantity"]
                  )

                Enum.min([10_000, aboard, q["demand"], div(q["buyer_budget"], max(1, q["bid"]))])

              company["unpaid"] > 0 || !CargoRules.compatible_cargo?(ship, item) ->
                0

              true ->
                capacity =
                  max(
                    0,
                    Enum.min([
                      10_000,
                      q["stock"],
                      div(class["weight"] - space.weight, item["weight_kg"]),
                      div(class["volume"] - space.volume, item["volume_l"])
                    ])
                  )

                largest_trade(0, capacity, fn quantity ->
                  voyage =
                    purchase_voyage(
                      ship,
                      item,
                      quantity,
                      destination,
                      view.private["ships"],
                      view.public["clock_ms"],
                      catalogue
                    )

                  voyage &&
                    Trading.purchase_total(q, ship, item, quantity) + voyage["required"] <= cash
                end)
            end

          {{side, good}, max(0, limit)}
        end
      )
    else
      %{}
    end
  end

  defp largest_trade(low, high, _feasible) when low == high, do: low

  defp largest_trade(low, high, feasible) do
    mid = div(low + high + 1, 2)

    if feasible.(mid),
      do: largest_trade(mid, high, feasible),
      else: largest_trade(low, mid - 1, feasible)
  end

  def purchase_voyage(ship, item, quantity, destination, fleet, clock, catalogue),
    do:
      Trading.purchase_voyage(
        ship,
        item,
        quantity,
        destination,
        Map.values(fleet),
        clock,
        catalogue
      )

  def trade_freshness(quote, ship, side, good, quantity, clock) do
    batches =
      if side == "buy",
        do: quote["freshness_batches"],
        else: Enum.filter(ship["cargo"], &(&1["good"] == good))

    CargoRules.freshness(batches, quantity, clock, CargoRules.handling_ms(quantity))
  end

  def route_distance(definitions, ship, destination) do
    if ship && ship["status"] == "docked" do
      if ship["port"] == destination,
        do: 0,
        else:
          get_in(definitions.catalogue, [
            "routes",
            ship["port"] <> "|" <> destination,
            "nautical_miles"
          ])
    end
  end

  def cargo_markets(_definitions, _view, nil, _side, _sort, _ship), do: []

  def cargo_markets(definitions, view, good, side, {column, direction}, ship) do
    rows =
      for {port, definition} <- definitions.catalogue["ports"],
          String.contains?(
            definition["roles"][good],
            if(side == "supply", do: "exp", else: "imp")
          ),
          quote = view.markets[port <> "|" <> good],
          quote["manual"],
          quote[if(side == "supply", do: "stock", else: "demand")] > 0,
          do:
            Map.merge(quote, %{
              "port" => port,
              "distance" => route_distance(definitions, ship, port)
            })

    if column in ["ask", "bid"] do
      quantity_key = if side == "supply", do: "stock", else: "demand"

      Enum.sort_by(rows, fn quote ->
        price = if direction == :asc, do: quote[column], else: -quote[column]

        {price, -quote[quantity_key],
         if(side == "demand", do: quote["distance"] || 1_000_000_000, else: 0), quote["port"]}
      end)
    else
      {known, unknown} = Enum.split_with(rows, &(not is_nil(&1[column])))

      Enum.sort_by(known, &{&1[column], &1["port"]}, direction) ++
        Enum.sort_by(unknown, & &1["port"])
    end
  end

  def manifest(cargo, catalogue) do
    cargo
    |> Enum.group_by(& &1["good"])
    |> Enum.sort_by(fn {good, _} -> catalogue["goods"][good]["name"] || good end)
    |> Enum.map(fn {good, batches} ->
      quantity = Enum.sum(Enum.map(batches, & &1["quantity"]))
      cost = Enum.sum(Enum.map(batches, &(&1["quantity"] * &1["unit_cost"])))
      expiries = batches |> Enum.map(& &1["expires_ms"]) |> Enum.reject(&is_nil/1)

      %{
        "good" => good,
        "quantity" => quantity,
        "average_cost" => cost / quantity,
        "expires_ms" => Enum.min(expiries, fn -> nil end)
      }
    end)
  end

  def visible_market_rows(definitions, view, ship, port) do
    definitions.catalogue["goods"]
    |> Enum.sort_by(fn {good, _} -> definitions.catalogue["goods"][good]["name"] || good end)
    |> Enum.filter(fn {good, _item} ->
      quote = view.markets[port <> "|" <> good]

      # Handling does not turn a local market into a remote-port preview.
      quote["manual"] and
        (is_nil(ship) or good in view.private["compatible_cargo"][ship["id"]]) and
        if ship && ship["port"] == port && ship["status"] != "sailing" do
          available_to_trade("buy", quote, ship, good) > 0 or
            available_to_trade("sell", quote, ship, good) > 0
        else
          quote["stock"] > 0 or quote["demand"] > 0
        end
    end)
  end

  def available_to_trade("buy", quote, _ship, _good), do: quote["stock"]

  def available_to_trade("sell", quote, ship, good),
    do: min(cargo_aboard(ship, good), quote["demand"])

  def cargo_aboard(ship, good) do
    (ship["cargo"] || [])
    |> Enum.filter(&(&1["good"] == good))
    |> Enum.map(& &1["quantity"])
    |> Enum.sum()
  end

  def sorted_manifest(cargo, goods, {column, direction}) do
    rows = manifest(cargo, %{"goods" => goods})
    # Non-perishable cargo always follows dated cargo when sorting by expiry.
    {undated, dated} =
      Enum.split_with(rows, &(column == "expires_ms" && is_nil(&1["expires_ms"])))

    Enum.sort_by(
      dated,
      fn row ->
        value =
          case column do
            "good" -> goods[row["good"]]["name"] || row["good"]
            "weight" -> row["quantity"] * goods[row["good"]]["weight_kg"]
            "volume" -> row["quantity"] * goods[row["good"]]["volume_l"]
            _ -> row[column]
          end

        {value, goods[row["good"]]["name"] || row["good"]}
      end,
      direction
    ) ++ undated
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
          min(10_000, cargo_aboard(ship, good))

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

  def cargo_options(definitions, view, sort_roi, ship \\ nil) do
    options =
      for {good, item} <-
            Enum.sort_by(definitions.catalogue["goods"], fn {good, item} ->
              item["name"] || good
            end),
          is_nil(ship) or compatible_cargo?(Map.put(ship, "cargo", []), item),
          asks = cargo_markets(definitions, view, good, "supply", {"ask", :asc}, nil),
          bids = cargo_markets(definitions, view, good, "demand", {"bid", :desc}, nil),
          asks != [] or bids != [] do
        ask =
          case asks do
            [q | _] -> q["ask"]
            [] -> nil
          end

        bid =
          case bids do
            [q | _] -> q["bid"]
            [] -> nil
          end

        {good, %{ask: ask, bid: bid, roi: if(bid && ask && ask > 0, do: (bid - ask) / ask)}}
      end

    if sort_roi do
      Enum.sort_by(options, fn {good, quote} ->
        {is_nil(quote.roi), -(quote.roi || 0),
         definitions.catalogue["goods"][good]["name"] || good}
      end)
    else
      options
    end
  end
end
