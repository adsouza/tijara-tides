defmodule TijaraTides.UseCases.VoyageOpportunities do
  @moduledoc "Bounded, read-only mixed-cargo estimates; suggestions, not an exact optimizer or orders."
  alias TijaraTides.Domain.{CargoRules, Fleet, Ship, Trading}

  def estimate(catalogue, view, ship, destination) do
    plans(catalogue, view, ship, destination)
    |> Enum.max_by(& &1.profit, fn -> nil end)
  end

  def tanker_estimate(catalogue, view, ship, destination) do
    plans(catalogue, view, ship, destination)
    |> Enum.map(fn plan ->
      {next_view, next_ship} = after_voyage(view, plan, destination)

      onward =
        catalogue["ports"]
        |> Map.keys()
        |> Enum.sort()
        |> Enum.filter(&(&1 != destination && catalogue["routes"][destination <> "|" <> &1]))
        |> Enum.flat_map(fn port ->
          case estimate(catalogue, next_view, next_ship, port) do
            %{purchases: [_ | _], profit: profit} = next when profit > 0 ->
              [Map.put(next, :destination, port)]

            _ ->
              []
          end
        end)
        |> Enum.max_by(& &1.profit, fn -> nil end)

      Map.merge(plan, %{
        onward: onward,
        combined_profit: plan.profit + if(onward, do: onward.profit, else: 0)
      })
    end)
    |> Enum.max_by(& &1.combined_profit, fn -> nil end)
  end

  defp after_voyage(view, plan, destination) do
    sold = Map.new(plan.sales, &{&1.good, &1.lots})

    {cargo, _} =
      Enum.map_reduce(plan.ship["cargo"], sold, fn batch, remaining ->
        quantity =
          if batch["expires_ms"] && batch["expires_ms"] <= plan.arrival,
            do: 0,
            else: batch["quantity"]

        n = min(quantity, Map.get(remaining, batch["good"], 0))

        {Map.put(batch, "quantity", quantity - n),
         Map.update(remaining, batch["good"], 0, &(&1 - n))}
      end)

    ship =
      Map.merge(plan.ship, %{
        "cargo" => Enum.filter(cargo, &(&1["quantity"] > 0)),
        "port" => destination,
        "status" => "docked",
        "arrive_ms" => nil,
        "crew_remainder" => 0
      })

    markets =
      Enum.reduce(plan.purchases, view.markets, fn p, markets ->
        update_in(markets, [plan.ship["port"] <> "|" <> p.good, "stock"], &max(0, &1 - p.lots))
      end)

    markets =
      Enum.reduce(plan.sales, markets, fn sale, markets ->
        Map.update!(markets, destination <> "|" <> sale.good, fn q ->
          %{
            q
            | "demand" => max(0, q["demand"] - sale.lots),
              "buyer_budget" => max(0, q["buyer_budget"] - sale.lots * q["bid"])
          }
        end)
      end)

    company =
      Map.merge(view.private["company"], %{"cash" => plan.remaining_cash, "reserved" => 0})

    next_view = %{
      view
      | markets: markets,
        public: Map.put(view.public, "clock_ms", plan.finish),
        private:
          view.private
          |> Map.put("company", company)
          |> update_in(["ships"], &Map.put(&1, ship["id"], ship))
    }

    {next_view, ship}
  end

  defp plans(catalogue, view, ship, destination) do
    clock = view.public["clock_ms"]
    company = view.private["company"]
    cash = max(0, company["cash"] - company["reserved"])

    context = %{
      catalogue: catalogue,
      view: view,
      destination: destination,
      clock: clock,
      cash: cash,
      # The fleet as the purchase command sees it: this ship before any planned purchase.
      fleet: Map.values(Map.put(view.private["ships"], ship["id"], ship))
    }

    base = %{ship: ship, purchases: [], spent: 0, loading: remaining_handling(ship, clock)}

    candidates =
      for {id, item} <- catalogue["goods"],
          item = Map.put(item, "id", id),
          source = view.markets[ship["port"] <> "|" <> id],
          buyer = view.markets[destination <> "|" <> id],
          source && buyer && source["manual"] && buyer["manual"],
          source["stock"] > 0 && capacity(buyer) > 0,
          CargoRules.compatible_cargo?(ship, item),
          margin = buyer["bid"] - buyer["handling_fee"] - source["ask"] - source["handling_fee"],
          margin > 0 do
        %{id: id, item: item, source: source, buyer: buyer, margin: margin}
      end

    # Different scarce resources favor different mixes. Evaluate deterministic greedy
    # alternatives and each first cargo, then keep the best funded complete plan.
    orders =
      for metric <- [:weight, :volume, :cash, :lot] do
        Enum.sort_by(candidates, fn c ->
          denominator =
            case metric do
              :weight -> c.item["weight_kg"]
              :volume -> c.item["volume_l"]
              :cash -> c.source["ask"] + c.source["handling_fee"]
              :lot -> 1
            end

          {-c.margin / max(1, denominator), c.id}
        end)
      end

    orders =
      orders ++ Enum.map(candidates, fn c -> [c | Enum.reject(hd(orders), &(&1.id == c.id))] end)

    plans =
      if company["unpaid"] > 0 or ship["pending_side"],
        do: [],
        else:
          Enum.map(Enum.uniq(orders), fn order ->
            Enum.reduce(order, base, fn candidate, plan ->
              add_purchase(plan, candidate, context)
            end)
          end)

    [base | plans]
    |> Enum.map(&evaluate(&1, context))
    |> Enum.filter(& &1.funded)
  end

  defp add_purchase(plan, c, ctx) do
    aboard = Enum.sum(for b <- plan.ship["cargo"], b["good"] == c.id, do: b["quantity"])

    # The purchase command's own limits, then what the destination buyer can take.
    limit =
      Trading.purchase_limits(c.source, plan.ship, c.item, ctx.clock, 0, ctx.catalogue)
      |> Map.values()
      |> Enum.min()
      |> min(capacity(c.buyer) - aboard)
      |> max(0)

    if CargoRules.compatible_cargo?(plan.ship, c.item) do
      quantity =
        TijaraTides.UseCases.MarketQueries.largest_trade(0, limit, fn n ->
          evaluate(purchase(plan, c, n, ctx), ctx).funded
        end)

      proposal = purchase(plan, c, quantity, ctx)
      if evaluate(proposal, ctx).profit > evaluate(plan, ctx).profit, do: proposal, else: plan
    else
      plan
    end
  end

  defp purchase(plan, _candidate, 0, _ctx), do: plan

  defp purchase(plan, c, n, ctx) do
    spent = Trading.purchase_total(c.source, plan.ship, c.item, n)
    cleaning = spent - n * (c.source["ask"] + c.source["handling_fee"])

    # The same lots and hold-rate expiries the purchase would load.
    batches =
      for b <-
            Trading.purchased_cargo(c.source, plan.ship, c.item, n, ctx.clock, 0, ctx.catalogue),
          do: Map.put(b, "unit_cost", c.source["ask"] + c.source["handling_fee"])

    %{
      plan
      | ship:
          plan.ship
          |> Map.update!("cargo", &(&1 ++ batches))
          |> then(fn ship ->
            if Fleet.classes()[ship["class"]]["hold"] == "liquid",
              do: Map.put(ship, "last_liquid", c.id),
              else: ship
          end),
        purchases: plan.purchases ++ [%{good: c.id, lots: n}],
        spent: plan.spent + spent,
        loading:
          plan.loading +
            CargoRules.loading_ms(
              CargoRules.handling_ms(
                n,
                c.source["handling_profile"] || CargoRules.handling_profile(nil, nil, %{})
              ),
              cleaning
            )
    }
  end

  defp funded?(plan, ctx) do
    case Trading.voyage_requirement(
           plan.ship,
           plan.loading,
           ctx.destination,
           ctx.fleet,
           ctx.clock,
           ctx.catalogue
         ) do
      nil -> false
      voyage -> plan.spent + voyage["required"] <= ctx.cash
    end
  end

  defp evaluate(plan, ctx) do
    voyage =
      Fleet.voyage_quote(
        plan.ship,
        ctx.destination,
        ctx.catalogue,
        ctx.clock + plan.loading,
        ctx.clock
      )

    arrival = ctx.clock + plan.loading + voyage["duration_ms"]

    {sales, proceeds, basis} =
      plan.ship["cargo"]
      |> Enum.group_by(& &1["good"])
      |> Enum.sort()
      |> Enum.reduce({[], 0, 0}, fn {good, batches}, {sales, proceeds, basis} ->
        buyer = ctx.view.markets[ctx.destination <> "|" <> good]

        {left, revenue, cost} =
          Enum.reduce(batches, {capacity(buyer), 0, 0}, fn b, {left, revenue, cost} ->
            expired = b["expires_ms"] && b["expires_ms"] <= arrival
            n = if expired, do: 0, else: min(left, b["quantity"])
            lost_basis = if expired, do: b["quantity"] * b["unit_cost"], else: 0

            sale = if n > 0, do: Trading.sale_proceeds(buyer, n), else: 0
            {left - n, revenue + sale, cost + n * b["unit_cost"] + lost_basis}
          end)

        lots = capacity(buyer) - left

        {if(lots > 0, do: sales ++ [%{good: good, lots: lots}], else: sales), proceeds + revenue,
         basis + cost}
      end)

    unloading =
      Enum.sum(
        Enum.map(sales, &CargoRules.handling_ms(&1.lots, ctx.destination, &1.good, ctx.catalogue))
      )

    horizon = plan.loading + voyage["duration_ms"] + unloading
    upkeep = upkeep(plan.ship, ctx.clock, horizon, voyage["sailing_ms"] || voyage["duration_ms"])
    maintenance = Fleet.maintenance_estimate(plan.ship, ctx.clock, ctx.clock + horizon)
    costs = voyage["fuel"] + voyage["canal_fees"] + upkeep - maintenance
    # Reserve fleet upkeep through completion without attributing other ships' costs
    # to this voyage's profit. No destination sale proceeds finance departure.
    fleet_reserve =
      Enum.sum(
        for {id, vessel} <- ctx.view.private["ships"], id != plan.ship["id"] do
          sailing =
            if vessel["status"] == "sailing",
              do: Fleet.moving_time(vessel, ctx.clock, ctx.clock + horizon),
              else: 0

          upkeep(vessel, ctx.clock, horizon, sailing)
        end
      )

    cleaning =
      plan.spent -
        Enum.sum(
          for p <- plan.purchases do
            q = ctx.view.markets[plan.ship["port"] <> "|" <> p.good]
            p.lots * (q["ask"] + q["handling_fee"])
          end
        )

    %{
      ship: plan.ship,
      arrival: arrival,
      finish: ctx.clock + horizon,
      remaining_cash: ctx.cash - plan.spent - costs - maintenance - fleet_reserve + proceeds,
      profit: proceeds - basis - costs - cleaning,
      costs: costs + cleaning,
      proceeds: proceeds,
      purchases: plan.purchases,
      sales: sales,
      spent: plan.spent,
      # Funding is the purchase command's own requirement; unloading counts only in profit.
      funded: funded?(plan, ctx)
    }
  end

  defp upkeep(ship, clock, horizon, sailing),
    do:
      Ship.crew_estimate(ship, sailing, horizon - sailing) +
        Fleet.maintenance_estimate(ship, clock, clock + horizon)

  defp capacity(%{"manual" => true} = q), do: Trading.sale_capacity(q)

  defp capacity(_), do: 0

  defp remaining_handling(%{"status" => status} = ship, clock)
       when status in ["loading", "unloading"],
       do: max(0, ship["arrive_ms"] - clock)

  defp remaining_handling(_, _), do: 0
end
