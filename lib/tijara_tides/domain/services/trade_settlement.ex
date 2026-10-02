defmodule TijaraTides.Domain.Services.TradeSettlement do
  alias TijaraTides.Domain.CompanyFinanceWorld
  alias TijaraTides.Domain.PortCargoMarketWorld

  @moduledoc "Atomic manual trades across company cash, ship cargo and market liquidity, with journal postings."
  import TijaraTides.Domain.State
  import TijaraTides.Domain.Fleet, only: [classes: 0, capacity: 2, voyage_quote: 5]
  import TijaraTides.Domain.CargoRules, only: [compatible_cargo?: 2, handling_ms: 4, max_lots: 0]
  import TijaraTides.Domain.PortCargoMarketWorld, only: [quote: 4]
  import TijaraTides.Domain.PortCargoMarket, only: [handling_rate: 1]

  @doc """
  The cargo a purchase of `quantity` loads. Perishables come from the market's
  soonest-expiring qualifying lots, aged at the ship's hold rate; fewer lots than
  requested means fresh stock is short. The purchase check and voyage planners
  share it, so a plan never assumes cargo outlasts what the purchase delivers.
  """
  def purchased_cargo(quote, ship, item, quantity, clock, minimum, catalogue) do
    if (item["shelf_ms"] || 0) > 0 do
      rate = TijaraTides.Domain.CargoRules.hold_rate(ship, catalogue)

      (quote["freshness_batches"] || [])
      |> Enum.filter(&TijaraTides.Domain.CargoRules.qualifies_batch?(&1, clock, minimum, rate))
      |> Enum.reduce({[], quantity}, fn b, {taken, left} ->
        n = min(left, b["quantity"])

        if n > 0 do
          aged =
            TijaraTides.Domain.CargoFreshness.recondition(
              %{expires_ms: b["expires_ms"], freshness: b["freshness"]},
              clock,
              rate,
              item
            )

          {taken ++ [%{"good" => item["id"], "quantity" => n, "expires_ms" => aged.expires_ms}],
           left - n}
        else
          {taken, left}
        end
      end)
      |> elem(0)
    else
      [%{"good" => item["id"], "quantity" => quantity}]
    end
  end

  @doc """
  Most lots one purchase may take under each limit: lots per command, market
  stock, the ship's hold, and stock that stays fresh in this hold. The buy command
  rejects more than a limit with that limit's error; read models offer the least.
  """
  def purchase_limits(quote, ship, item, clock, minimum, catalogue) do
    class = classes()[ship["class"]]
    space = capacity(ship, catalogue)
    stock = max(0, quote["stock"])

    %{
      lots: max_lots(),
      stock: stock,
      hold:
        max(
          0,
          min(
            div(class["weight"] - space.weight, item["weight_kg"]),
            div(class["volume"] - space.volume, item["volume_l"])
          )
        ),
      fresh:
        if((item["shelf_ms"] || 0) > 0,
          do:
            Enum.sum(
              for b <- purchased_cargo(quote, ship, item, stock, clock, minimum, catalogue),
                  do: b["quantity"]
            ),
          else: stock
        )
    }
  end

  @doc """
  The cash a purchase may spend under the visit's budget. A strict budget spends
  only its reserved remainder and leaves the voyage funded from free cash; a skip
  decision or unpaid bills block purchases. Purchases and read models share it.
  """
  def purchasing_terms(company, budget, ship) do
    available = company["cash"] - company["reserved"]

    strict =
      budget != nil and budget["strict"] == true and budget["ship_id"] == ship["id"] and
        budget["port"] == ship["port"] and budget["company_id"] == company["id"]

    %{
      available: available,
      purchase_cash: if(strict, do: budget["remaining"], else: available),
      strict: strict,
      blocked: (budget != nil and budget["skip"] == true) or company["unpaid"] > 0
    }
  end

  @doc "The funding check a purchase of `total` fails, with the onward voyage needing `required`."
  def purchase_shortfall(terms, total, required) do
    cond do
      terms.blocked or terms.purchase_cash < total ->
        :purchase

      required != nil and terms.available - if(terms.strict, do: 0, else: total) < required ->
        :voyage

      true ->
        nil
    end
  end

  def execute(
        state,
        account,
        %TijaraTides.Domain.Trade{} = trade,
        catalogue,
        admission \\ :normal
      ) do
    result = check(state, account, trade, catalogue)

    case result do
      {:ok, changed, reply} ->
        ship = get(state, "ships", trade.ship_id)

        available =
          if admission == :manual,
            do: TijaraTides.Domain.PortBerthsWorld.ready_available?(state, ship, catalogue),
            else: TijaraTides.Domain.PortBerthsWorld.available?(state, ship, catalogue)

        if available do
          changed =
            TijaraTides.Domain.Services.ShipLifecycle.admit_handling(changed, trade.ship_id)

          {:ok, changed, reply}
        else
          {:error, :berth_busy}
        end

      _ ->
        result
    end
  end

  @doc "Validate speculatively with local lot IDs; no simulated changes may escape this check."
  def validate(state, account, trade, catalogue) do
    case check(Map.put(state, :lot_allocation, {:local, 1}), account, trade, catalogue) do
      {:ok, _, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  def check(state, account, trade, catalogue) do
    state = TijaraTides.Domain.Services.FinancialSettlement.settle(state, [account["company_id"]])

    trade(
      state,
      account,
      trade.side,
      trade.ship_id,
      trade.good,
      trade.quantity,
      trade.limit,
      trade.destination,
      trade.min_remaining_ms,
      trade.purchase_budget_id,
      trade,
      catalogue
    )
  end

  defp trade(
         state,
         account,
         action,
         ship_id,
         good,
         quantity,
         limit,
         destination,
         minimum,
         budget_id,
         terms,
         catalogue
       ) do
    with %{} = company <- get(state, "companies", account["company_id"]),
         %{"company_id" => owner, "status" => "docked"} = ship <- get(state, "ships", ship_id),
         true <- owner == company["id"] and is_nil(company["bankruptcy_ms"]),
         %{"manual" => true} = item <- catalogue["goods"][good],
         %{} <- get(state, "markets", ship["port"] <> "|" <> good),
         true <-
           is_integer(quantity) and quantity > 0 and quantity <= max_lots() and
             is_integer(limit) and
             limit >= 0 and TijaraTides.Domain.CargoRules.valid_remaining?(minimum) and
             TijaraTides.Domain.OrderBook.schedule?(terms.markdowns) and
             is_integer(terms.price_floor) and terms.price_floor in 0..1_000_000_000_000 and
             (terms.markdowns == nil or (action == "sell" and item["category"] == "Perishables")) do
      market = get(state, "markets", ship["port"] <> "|" <> good)
      quote = quote(state, catalogue, ship["port"], good)
      handling = quantity * handling_rate(catalogue["ports"][ship["port"]])

      if action == "buy",
        do:
          buy(
            state,
            company,
            ship,
            item,
            quantity,
            limit,
            market,
            quote,
            handling,
            destination,
            minimum,
            budget_id,
            catalogue
          ),
        else:
          sell(
            state,
            company,
            ship,
            good,
            quantity,
            limit,
            market,
            quote,
            handling,
            terms,
            catalogue
          )
    else
      _ -> {:error, :invalid_trade}
    end
  end

  def purchase_total(quote, ship, item, quantity) when quantity > 0 do
    quantity * (quote["ask"] + quote["handling_fee"]) + cleaning_cost(ship, item)
  end

  def purchase_total(_quote, _ship, _item, _quantity), do: 0

  # Estimate from the loaded ship, including this purchase. This is an affordability
  # check, not a cash reservation or an instruction to sail automatically.
  def purchase_voyage(ship, item, quantity, destination, fleet, clock, catalogue) do
    loaded =
      Map.update!(ship, "cargo", &(&1 ++ [%{"good" => item["id"], "quantity" => quantity}]))

    loading =
      TijaraTides.Domain.CargoRules.loading_ms(
        handling_ms(quantity, ship["port"], item["id"], catalogue),
        cleaning_cost(ship, item)
      )

    voyage_requirement(loaded, loading, destination, fleet, clock, catalogue)
  end

  @doc """
  The onward voyage a loaded ship must fund before it buys: fuel, canal fees and
  crew and maintenance upkeep for the whole fleet until it arrives. `nil` when
  there is no allowed voyage. Purchases and voyage planners share it.
  """
  def voyage_requirement(loaded, loading, destination, fleet, clock, catalogue) do
    with true <- is_binary(destination) and destination != loaded["port"],
         %{} = voyage <- voyage_quote(loaded, destination, catalogue, clock + loading, clock),
         true <- voyage["duration_ms"] <= TijaraTides.Domain.Fleet.max_voyage_ms() do
      horizon = loading + voyage["duration_ms"]

      upkeep =
        Enum.reduce(fleet, 0, fn vessel, total ->
          sailing =
            cond do
              vessel["id"] == loaded["id"] ->
                voyage["sailing_ms"] || voyage["duration_ms"]

              vessel["status"] == "sailing" ->
                TijaraTides.Domain.Fleet.moving_time(vessel, clock, clock + horizon)

              true ->
                0
            end

          total + TijaraTides.Domain.Ship.crew_estimate(vessel, sailing, horizon - sailing) +
            TijaraTides.Domain.ShipMaintenance.estimate(vessel, clock, clock + horizon)
        end)

      Map.merge(voyage, %{
        "loading_ms" => loading,
        "maintenance_estimate" =>
          TijaraTides.Domain.ShipMaintenance.estimate(loaded, clock + loading, clock + horizon),
        "upkeep" => upkeep,
        "required" => voyage["fuel"] + voyage["canal_fees"] + upkeep
      })
    else
      _ -> nil
    end
  end

  defp cleaning_cost(ship, item),
    do: TijaraTides.Domain.CargoRules.cleaning_cost(ship["last_liquid"], item)

  defp buy(
         state,
         company,
         ship,
         item,
         quantity,
         limit,
         market,
         quote,
         handling,
         destination,
         minimum,
         budget_id,
         catalogue
       ) do
    cleaning = cleaning_cost(ship, item)

    cost = quote["ask"] * quantity

    fleet =
      entities(state, "ships")
      |> Map.values()
      |> Enum.filter(&(&1["company_id"] == company["id"]))

    voyage = purchase_voyage(ship, item, quantity, destination, fleet, state.clock_ms, catalogue)

    budget =
      if budget_id,
        do: get(state, "visit_budgets", budget_id),
        else: TijaraTides.Domain.AutomationWorld.budget(state, ship, ship["port"])

    terms = purchasing_terms(company, budget, ship)
    limits = purchase_limits(quote, ship, item, state.clock_ms, minimum, catalogue)
    strict = terms.strict

    shortfall =
      purchase_shortfall(terms, cost + handling + cleaning, voyage && voyage["required"])

    cond do
      not market["seller"] ->
        {:error, :insufficient_supply}

      not compatible_cargo?(ship, item) ->
        {:error, :incompatible_cargo}

      quantity > limits.hold ->
        {:error, :capacity_exceeded}

      quote["ask"] > limit ->
        {:error, :price_changed}

      quantity > limits.stock ->
        {:error, :insufficient_supply}

      quantity > limits.fresh ->
        {:error, :insufficient_fresh_cargo}

      shortfall == :purchase ->
        {:error, :insufficient_cash}

      is_nil(voyage) ->
        {:error, :purchase_destination_required}

      shortfall == :voyage ->
        {:error,
         {:purchase_voyage_funds, destination, voyage["required"],
          company["cash"] - company["reserved"] - cost - handling - cleaning}}

      true ->
        {state, cargo} =
          PortCargoMarketWorld.release_stock(
            state,
            market["port"],
            market["good"],
            quantity,
            quote["ask"],
            item,
            minimum,
            %{receiving_bps: TijaraTides.Domain.CargoRules.hold_rate(ship, catalogue)}
          )

        state =
          TijaraTides.Domain.ShipWorld.load_cargo(state, ship["id"], cargo, cleaning, catalogue)

        state =
          PortCargoMarketWorld.protect_storage(
            state,
            market["port"],
            item["id"],
            get(state, "ships", ship["id"])["arrive_ms"]
          )

        state =
          CompanyFinanceWorld.post(
            state,
            company["id"],
            "purchase",
            [
              {"inventory", cost},
              {"handling_expense", handling},
              {"cleaning_expense", cleaning},
              {if(strict, do: "cash_reserved", else: "cash_available"),
               -cost - handling - cleaning}
            ],
            %{ship: ship["id"], good: item["id"]}
          )

        state =
          if strict,
            do:
              TijaraTides.Domain.AutomationWorld.consume_visit(
                state,
                budget["id"],
                cost + handling + cleaning
              ),
            else: state

        {:ok, state, %{"spent" => cost + handling + cleaning, "quantity" => quantity}}
    end
  end

  defp sell(
         state,
         company,
         ship,
         good,
         quantity,
         limit,
         market,
         quote,
         handling,
         terms,
         catalogue
       ) do
    available = TijaraTides.Domain.ShipWorld.cargo_available(state, ship["id"], good)

    qualified =
      Enum.filter(ship["cargo"], fn b ->
        b["good"] == good and (is_nil(b["expires_ms"]) or b["expires_ms"] > state.clock_ms) and
          TijaraTides.Domain.OrderBook.effective_price(
            %{
              initial_price: limit,
              price: limit,
              markdowns: terms.markdowns,
              price_floor: terms.price_floor
            },
            TijaraTides.Domain.OrderBook.grade_row(b, state.clock_ms)
          ) <= quote["bid"]
      end)

    cond do
      not market["buyer"] ->
        {:error, :insufficient_demand}

      available < quantity ->
        {:error, :insufficient_cargo}

      Enum.sum(for b <- qualified, do: b["quantity"]) < quantity ->
        {:error, :price_changed}

      quantity > TijaraTides.Domain.PortCargoMarket.sale_capacity(quote) ->
        {:error, :insufficient_demand}

      true ->
        {state, sold} =
          TijaraTides.Domain.ShipWorld.unload_cargo(
            state,
            ship["id"],
            good,
            quantity,
            Enum.map(qualified, & &1["lot_id"]),
            catalogue
          )

        cost = Enum.sum(Enum.map(sold, &(&1["quantity"] * &1["unit_cost"])))

        proceeds = TijaraTides.Domain.PortCargoMarket.sale_proceeds(quote, quantity)

        state =
          state
          |> PortCargoMarketWorld.accept_cargo(market["port"], good, quantity, quote["bid"], sold)
          |> PortCargoMarketWorld.protect_storage(
            market["port"],
            good,
            get(state, "ships", ship["id"])["arrive_ms"]
          )

        state =
          CompanyFinanceWorld.post(
            state,
            company["id"],
            "sale",
            [
              {"cash_available", proceeds},
              {"sales_revenue", -quote["bid"] * quantity},
              {"handling_expense", handling},
              {"cost_of_goods", cost},
              {"inventory", -cost}
            ],
            %{ship: ship["id"], good: good}
          )

        {:ok, TijaraTides.Domain.Services.FinancialSettlement.settle(state, [company["id"]]),
         %{"received" => proceeds, "quantity" => quantity}}
    end
  end
end
