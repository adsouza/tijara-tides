defmodule TijaraTides.Domain.Trading do
  @moduledoc "Atomic manual trades across company cash, ship cargo and market liquidity, with journal postings."
  import TijaraTides.Domain.State
  import TijaraTides.Domain.Fleet, only: [classes: 0, capacity: 2, voyage_quote: 3]
  import TijaraTides.Domain.CargoRules, only: [compatible_cargo?: 2, handling_ms: 1]
  import TijaraTides.Domain.Markets, only: [quote: 4, handling_rate: 1]
  alias TijaraTides.Domain.{CargoLots, Journal}

  def execute(state, account, %TijaraTides.Domain.Trade{} = trade, catalogue) do
    state = TijaraTides.Domain.Finance.settle(state)

    trade(
      state,
      account,
      trade.side,
      trade.ship_id,
      trade.good,
      trade.quantity,
      trade.limit,
      trade.destination,
      catalogue
    )
  end

  defp trade(state, account, action, ship_id, good, quantity, limit, destination, catalogue) do
    with %{} = company <- get(state, "companies", account["company_id"]),
         %{"company_id" => owner, "status" => "docked"} = ship <- get(state, "ships", ship_id),
         true <- owner == company["id"] and is_nil(company["bankruptcy_ms"]),
         %{"manual" => true} = item <- catalogue["goods"][good],
         %{"merchant" => false} <- get(state, "markets", ship["port"] <> "|" <> good),
         true <-
           is_integer(quantity) and quantity > 0 and quantity <= 10_000 and is_integer(limit) and
             limit >= 0 do
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
            catalogue
          ),
        else: sell(state, company, ship, good, quantity, limit, market, quote, handling)
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

    with true <- is_binary(destination) and destination != ship["port"],
         %{} = voyage <- voyage_quote(loaded, destination, catalogue),
         true <- voyage["duration_ms"] <= 86_400_000 do
      loading = handling_ms(quantity) + if(cleaning_cost(ship, item) > 0, do: 60_000, else: 0)
      horizon = loading + voyage["duration_ms"]

      upkeep =
        Enum.reduce(fleet, 0, fn vessel, total ->
          sailing =
            cond do
              vessel["id"] == ship["id"] -> voyage["duration_ms"]
              vessel["status"] == "sailing" -> min(horizon, max(0, vessel["arrive_ms"] - clock))
              true -> 0
            end

          numerator =
            (horizon + sailing) * classes()[vessel["class"]]["crew"] + vessel["crew_remainder"]

          total + div(numerator + 119_999, 120_000)
        end)

      Map.merge(voyage, %{
        "upkeep" => upkeep,
        "required" => voyage["fuel"] + voyage["canal_fees"] + upkeep
      })
    else
      _ -> nil
    end
  end

  defp cleaning_cost(ship, item) do
    if classes()[ship["class"]]["hold"] == "liquid" and
         ship["last_liquid"] not in [nil, item["id"]],
       do: if("vegetable_oil" in [ship["last_liquid"], item["id"]], do: 25_000, else: 5000),
       else: 0
  end

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
         catalogue
       ) do
    class = classes()[ship["class"]]
    space = capacity(ship, catalogue)

    cleaning = cleaning_cost(ship, item)

    cost = quote["ask"] * quantity

    fleet =
      entities(state, "ships")
      |> Map.values()
      |> Enum.filter(&(&1["company_id"] == company["id"]))

    voyage = purchase_voyage(ship, item, quantity, destination, fleet, state.clock_ms, catalogue)

    cond do
      not compatible_cargo?(ship, item) ->
        {:error, :incompatible_cargo}

      space.weight + quantity * item["weight_kg"] > class["weight"] or
          space.volume + quantity * item["volume_l"] > class["volume"] ->
        {:error, :capacity_exceeded}

      quote["ask"] > limit ->
        {:error, :price_changed}

      market["stock"] < quantity ->
        {:error, :insufficient_supply}

      company["cash"] - company["reserved"] < cost + handling + cleaning or company["unpaid"] > 0 ->
        {:error, :insufficient_cash}

      is_nil(voyage) ->
        {:error, :purchase_destination_required}

      company["cash"] - company["reserved"] - cost - handling - cleaning < voyage["required"] ->
        {:error,
         {:purchase_voyage_funds, destination, voyage["required"],
          company["cash"] - company["reserved"] - cost - handling - cleaning}}

      true ->
        {state, batches, remaining} =
          if item["shelf_ms"] > 0 do
            CargoLots.take(state, market["batches"], quantity, item["id"])
          else
            {next, lot} = CargoLots.create(state, item["id"], quantity, nil)
            {next, [lot], []}
          end

        cargo =
          Enum.map(batches, &Map.merge(&1, %{"good" => item["id"], "unit_cost" => quote["ask"]}))

        market = %{market | "batches" => remaining, "budget" => market["budget"] + cost}

        ship = %{
          ship
          | "cargo" => ship["cargo"] ++ cargo,
            "status" => "loading",
            "arrive_ms" =>
              state.clock_ms + handling_ms(quantity) + if(cleaning > 0, do: 60_000, else: 0),
            "last_liquid" =>
              if(class["hold"] == "liquid", do: item["id"], else: ship["last_liquid"])
        }

        company = %{
          company
          | "cash" => company["cash"] - cost - handling - cleaning,
            "profit" => company["profit"] - handling - cleaning
        }

        state =
          state
          |> put("ships", ship["id"], ship)
          |> put("companies", company["id"], company)
          |> put("markets", market["port"] <> "|" <> market["good"], %{
            market
            | "stock" => market["stock"] - quantity
          })

        state =
          Journal.post(
            state,
            company["id"],
            "purchase",
            [
              {"inventory", cost},
              {"handling_expense", handling},
              {"cleaning_expense", cleaning},
              {"cash_available", -cost - handling - cleaning}
            ],
            %{ship: ship["id"], good: item["id"]}
          )

        {:ok, state, %{"spent" => cost + handling + cleaning, "quantity" => quantity}}
    end
  end

  defp sell(state, company, ship, good, quantity, limit, market, quote, handling) do
    available = Enum.sum(for b <- ship["cargo"], b["good"] == good, do: b["quantity"])

    cond do
      available < quantity ->
        {:error, :insufficient_cargo}

      quote["bid"] < limit ->
        {:error, :price_changed}

      market["demand"] < quantity or market["budget"] < quote["bid"] * quantity ->
        {:error, :insufficient_demand}

      true ->
        {state, sold, cargo} = CargoLots.take(state, ship["cargo"], quantity, good)
        cost = Enum.sum(Enum.map(sold, &(&1["quantity"] * &1["unit_cost"])))

        proceeds = quote["bid"] * quantity - handling
        paid = min(company["unpaid"], max(0, proceeds))

        company = %{
          company
          | "cash" => company["cash"] + proceeds - paid,
            "unpaid" => company["unpaid"] - paid,
            "profit" => company["profit"] + proceeds - cost
        }

        ship = %{
          ship
          | "cargo" => cargo,
            "status" => "unloading",
            "arrive_ms" => state.clock_ms + handling_ms(quantity)
        }

        market = %{
          market
          | "demand" => market["demand"] - quantity,
            "budget" => market["budget"] - quote["bid"] * quantity,
            "stock" => market["stock"] + if(market["merchant"], do: quantity, else: 0)
        }

        state =
          state
          |> put("ships", ship["id"], ship)
          |> put("companies", company["id"], company)
          |> put("markets", market["port"] <> "|" <> good, market)

        state =
          Journal.post(
            state,
            company["id"],
            "sale",
            [
              {"cash_available", proceeds - paid},
              {"sales_revenue", -quote["bid"] * quantity},
              {"handling_expense", handling},
              {"cost_of_goods", cost},
              {"inventory", -cost},
              {"payables", paid}
            ],
            %{ship: ship["id"], good: good}
          )

        {:ok, TijaraTides.Domain.Finance.settle(state),
         %{"received" => proceeds, "quantity" => quantity}}
    end
  end
end
