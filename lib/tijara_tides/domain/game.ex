defmodule TijaraTides.Domain.Game do
  @moduledoc "Pure first-playtest rules. All time, credentials, IDs and catalogue data are supplied."
  alias TijaraTides.Domain.{CargoLots, Journal}
  @invite_ms 3 * 86_400_000
  @asset_value 20_000_000
  @voyage_speedup 600
  @minimum_voyage_ms 6_000
  @market_replenishment_ms 150_000

  def classes do
    %{
      "freighter" => %{
        "name" => "Balanced freighter",
        "price" => 4_000_000,
        "weight" => 500_000,
        "volume" => 900_000,
        "hold" => "dry",
        "speed" => 22,
        "crew" => 30
      },
      "small_freighter" => %{
        "name" => "Small freighter",
        "price" => 3_000_000,
        "weight" => 200_000,
        "volume" => 400_000,
        "hold" => "dry",
        "speed" => 24,
        "crew" => 20
      },
      "bulk" => %{
        "name" => "Bulk carrier",
        "price" => 5_000_000,
        "weight" => 1_000_000,
        "volume" => 1_200_000,
        "hold" => "dry",
        "speed" => 18,
        "crew" => 40
      },
      "reefer" => %{
        "name" => "Small refrigerated ship",
        "price" => 5_000_000,
        "weight" => 200_000,
        "volume" => 400_000,
        "hold" => "reefer",
        "speed" => 24,
        "crew" => 35
      },
      "tanker" => %{
        "name" => "Small tanker",
        "price" => 5_000_000,
        "weight" => 500_000,
        "volume" => 650_000,
        "hold" => "liquid",
        "speed" => 20,
        "crew" => 35
      }
    }
  end

  def packages do
    %{
      "general" => ["freighter", "freighter", "freighter"],
      "bulk" => ["bulk", "bulk", "small_freighter"],
      "fresh" => ["reefer", "reefer", "freighter"],
      "oil" => ["tanker", "tanker", "freighter"]
    }
  end

  def package_cash(package),
    do: @asset_value - Enum.sum(Enum.map(packages()[package], &classes()[&1]["price"]))

  def entities(state, kind), do: Map.get(state.entities, kind, %{})
  def get(state, kind, id), do: entities(state, kind)[id]

  def put(state, kind, id, value),
    do: %{
      state
      | entities: Map.update(state.entities, kind, %{id => value}, &Map.put(&1, id, value))
    }

  def delete(state, "companies", id) do
    if Enum.any?(entities(state, "ships"), fn {_, ship} -> ship["company_id"] == id end),
      do: raise(ArgumentError, "retire or transfer ships before removing a company")

    %{state | entities: Map.update(state.entities, "companies", %{}, &Map.delete(&1, id))}
  end

  def delete(state, kind, id),
    do: %{state | entities: Map.update(state.entities, kind, %{}, &Map.delete(&1, id))}

  def initialize(state, catalogue) do
    validate_catalogue!(catalogue)
    state = prune_notices(state)

    if map_size(entities(state, "markets")) == 0 do
      Enum.reduce(catalogue["ports"], state, fn {port, definition}, state ->
        Enum.reduce(definition["roles"], state, fn {good, role}, state ->
          merchant = String.contains?(role, "/")
          seller = String.contains?(role, "exp")
          buyer = String.contains?(role, "imp")

          item = catalogue["goods"][good]

          {state, batches} =
            if item["shelf_ms"] > 0 and seller and not merchant do
              {next, lot} = CargoLots.create(state, good, 500, state.clock_ms + item["shelf_ms"])
              {next, [lot]}
            else
              {state, []}
            end

          market = %{
            "port" => port,
            "good" => good,
            "merchant" => merchant,
            "seller" => seller,
            "buyer" => buyer,
            "stock" => if(seller and not merchant, do: 500, else: 0),
            "demand" => if(buyer, do: 500, else: 0),
            "budget" => item["reference_cents"] * 1000,
            "batches" => batches,
            "last_production" => state.clock_ms
          }

          put(state, "markets", port <> "|" <> good, market)
        end)
      end)
    else
      state
    end
  end

  def authenticate(state, session_hash, wall_ms) do
    case get(state, "sessions", session_hash) do
      %{"account_id" => id, "expires_at" => expiry} when expiry > wall_ms ->
        case get(state, "accounts", id) do
          nil -> {:error, :invalid_session}
          account -> {:ok, account}
        end

      _ ->
        {:error, :invalid_session}
    end
  end

  def execute(state, account, command, context, catalogue) do
    case command do
      %{"action" => "company", "name" => name, "port" => port, "package" => package} ->
        create_company(state, account, name, port, package, context)

      %{"action" => "invite"} ->
        issue_invite(state, account, context)

      %{
        "action" => action,
        "ship" => ship_id,
        "good" => good,
        "quantity" => quantity,
        "limit" => limit
      }
      when action in ["buy", "sell"] ->
        trade(
          state,
          account,
          action,
          ship_id,
          good,
          quantity,
          limit,
          command["destination"],
          catalogue
        )

      %{"action" => "sail", "ship" => id, "destination" => destination, "fuel_limit" => limit} ->
        sail(state, account, id, destination, limit, catalogue)

      _ ->
        {:error, :unsupported_command}
    end
  end

  def seed_invite(state, hash) do
    if get(state, "invitations", hash),
      do: {:error, :already_exists},
      else:
        {:ok,
         put(state, "invitations", hash, %{
           "inviter" => nil,
           "expires_ms" => state.clock_ms + @invite_ms,
           "status" => "issued",
           "seed" => true
         }), %{"created" => true}}
  end

  def redeem(state, hash, session_hash, context) do
    case get(state, "invitations", hash) do
      %{"status" => "redeemed", "invitee" => account_id} ->
        case authenticate(state, session_hash, context.wall_ms) do
          {:ok, %{"id" => ^account_id}} -> {:replay, %{"account_id" => account_id}}
          _ -> {:error, :invalid_invitation}
        end

      _ ->
        # A device credential can bootstrap only one account. Never overwrite a
        # session when concurrent forms submit two different invitations.
        if get(state, "sessions", session_hash),
          do: {:error, :invalid_invitation},
          else: redeem_new(state, hash, session_hash, context)
    end
  end

  defp redeem_new(state, hash, session_hash, context) do
    with %{"status" => "issued", "expires_ms" => expiry} = invite <-
           get(state, "invitations", hash),
         true <- state.clock_ms < expiry do
      id = context.id

      account = %{
        "id" => id,
        "company_id" => nil,
        "inviter" => invite["inviter"],
        "bankruptcies" => 0,
        "invite_quota" => if(invite["seed"], do: 3, else: 0),
        "created_ms" => state.clock_ms
      }

      state =
        state
        |> put("accounts", id, account)
        |> put("sessions", session_hash, %{
          "account_id" => id,
          "expires_at" => context.wall_ms + 365 * 86_400_000
        })
        |> put("invitations", hash, Map.merge(invite, %{"status" => "redeemed", "invitee" => id}))

      state =
        notice(
          state,
          invite["inviter"],
          "accepted:" <> id,
          "Your invitation was accepted. Company formation is pending."
        )

      {:ok, state, %{"account_id" => id}}
    else
      _ -> {:error, :invalid_invitation}
    end
  end

  defp create_company(state, account, name, port, package, context) do
    name = if is_binary(name), do: String.trim(name), else: ""

    cond do
      account["company_id"] != nil ->
        {:error, :company_exists}

      name == "" or String.length(name) > 60 ->
        {:error, :invalid_name}

      not Map.has_key?(context.catalogue["ports"], port) ->
        {:error, :invalid_port}

      not Map.has_key?(packages(), package) ->
        {:error, :invalid_package}

      Enum.any?(entities(state, "companies"), fn {_, c} ->
        String.downcase(c["name"]) == String.downcase(name)
      end) ->
        {:error, :name_taken}

      true ->
        id = context.id

        company = %{
          "id" => id,
          "account_id" => account["id"],
          "name" => name,
          "home" => port,
          "cash" => package_cash(package),
          "reserved" => 0,
          "profit" => 0,
          "unpaid" => 0,
          "created_ms" => state.clock_ms,
          "last_invite_year" => 0
        }

        state =
          state
          |> put("companies", id, company)
          |> put("accounts", account["id"], %{account | "company_id" => id})

        state =
          packages()[package]
          |> Enum.with_index(1)
          |> Enum.reduce(state, fn {class, index}, state ->
            ship_id = id <> ":" <> to_string(index)

            ship = %{
              "id" => ship_id,
              "company_id" => id,
              "name" => "#{name} #{index}",
              "class" => class,
              "book_value" => classes()[class]["price"],
              "port" => port,
              "cargo" => [],
              "status" => "docked",
              "arrive_ms" => nil,
              "destination" => nil,
              "depart_ms" => nil,
              "fuel_total" => 0,
              "fuel_burned" => 0,
              "crew_remainder" => 0,
              "last_cost_ms" => state.clock_ms,
              "last_liquid" => nil
            }

            put(state, "ships", ship_id, ship)
          end)

        state =
          notice(state, account["inviter"], "company:" <> id, "Your invitee now runs #{name}.")

        fleet = Enum.sum(Enum.map(packages()[package], &classes()[&1]["price"]))

        state =
          Journal.post(state, id, "starter_grant", [
            {"cash_available", package_cash(package)},
            {"fleet", fleet},
            {"capital", -package_cash(package) - fleet}
          ])

        {:ok, state, %{"company_id" => id}}
    end
  end

  defp issue_invite(state, account, context) do
    outstanding =
      Enum.count(entities(state, "invitations"), fn {_, i} ->
        i["inviter"] == account["id"] and i["status"] == "issued"
      end)

    if account["invite_quota"] > 0 and outstanding < 3 do
      state =
        state
        |> put("accounts", account["id"], %{
          account
          | "invite_quota" => account["invite_quota"] - 1
        })
        |> put("invitations", context.invite_hash, %{
          "inviter" => account["id"],
          "expires_ms" => state.clock_ms + @invite_ms,
          "status" => "issued",
          "seed" => false
        })

      {:ok, state,
       %{"invitation" => context.invite_hash, "expires_ms" => state.clock_ms + @invite_ms}}
    else
      {:error, :no_invitation_quota}
    end
  end

  def quote(state, catalogue, port, good) do
    market = get(state, "markets", port <> "|" <> good)
    item = catalogue["goods"][good]

    if market && item do
      clustered = Enum.any?(catalogue["clusters"], fn {_, ports} -> port in ports end)
      ask_base = if market["merchant"] or clustered, do: 105, else: 90
      bid_base = if market["merchant"] or clustered, do: 95, else: 110

      %{
        "ask" => div(item["reference_cents"] * (ask_base + div(500 - market["stock"], 25)), 100),
        "bid" => div(item["reference_cents"] * (bid_base - div(500 - market["demand"], 25)), 100),
        "handling_fee" => handling_rate(catalogue["ports"][port]),
        "freshness_batches" => market["batches"],
        "stock" => market["stock"],
        "demand" => market["demand"],
        "buyer_budget" => market["budget"],
        "manual" => item["manual"] and not market["merchant"]
      }
    end
  end

  def capacity(ship, catalogue) do
    Enum.reduce(ship["cargo"], %{weight: 0, volume: 0}, fn batch, totals ->
      item = catalogue["goods"][batch["good"]]

      %{
        weight: totals.weight + item["weight_kg"] * batch["quantity"],
        volume: totals.volume + item["volume_l"] * batch["quantity"]
      }
    end)
  end

  defp trade(state, account, action, ship_id, good, quantity, limit, destination, catalogue) do
    with %{} = company <- get(state, "companies", account["company_id"]),
         %{"company_id" => owner, "status" => "docked"} = ship <- get(state, "ships", ship_id),
         true <- owner == company["id"],
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

  def compatible_cargo?(ship, item) do
    hold = classes()[ship["class"]]["hold"]
    supported = item["hold"] == hold or (hold == "reefer" and item["hold"] == "dry")
    supported and (hold != "liquid" or Enum.all?(ship["cargo"], &(&1["good"] == item["id"])))
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
       do: if("Vegetable oil" in [ship["last_liquid"], item["id"]], do: 25_000, else: 5000),
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

        {:ok, state, %{"received" => proceeds, "quantity" => quantity}}
    end
  end

  def handling_ms(quantity), do: max(1000, quantity * 500)

  def freshness(batches, quantity, clock, elapsed) do
    {expiries, _} =
      Enum.reduce(batches, {[], max(0, quantity)}, fn batch, {expiries, left} ->
        take = min(left, batch["quantity"])

        expiries =
          if take > 0 and batch["expires_ms"],
            do: [batch["expires_ms"] | expiries],
            else: expiries

        {expiries, left - take}
      end)

    case expiries do
      [] ->
        nil

      _ ->
        first = Enum.min(expiries)

        %{
          "remaining_ms" => max(0, first - clock),
          "after_ms" => max(0, first - clock - elapsed),
          "handling_ms" => elapsed
        }
    end
  end

  def voyage_freshness(ship, clock, duration) do
    unloading = ship["cargo"] |> Enum.map(& &1["quantity"]) |> Enum.sum() |> handling_ms()

    ship["cargo"]
    |> Enum.group_by(& &1["good"])
    |> Enum.sort()
    |> Enum.flat_map(fn {good, batches} ->
      quantity = Enum.sum(Enum.map(batches, & &1["quantity"]))

      case freshness(batches, quantity, clock, duration) do
        nil ->
          []

        estimate ->
          [
            %{
              "good" => good,
              "quantity" => quantity,
              "arrival_ms" => estimate["after_ms"],
              "unloaded_ms" => max(0, estimate["after_ms"] - unloading)
            }
          ]
      end
    end)
  end

  def voyage_quote(ship, destination, catalogue) when is_binary(destination) do
    case catalogue["routes"][ship["port"] <> "|" <> destination] do
      nil ->
        nil

      route ->
        class = classes()[ship["class"]]
        space = capacity(ship, catalogue)
        fuel = route["nautical_miles"] * (8 + div(space.weight * 8, class["weight"]))

        duration =
          max(
            @minimum_voyage_ms,
            div(route["nautical_miles"] * 3_600_000, class["speed"] * @voyage_speedup)
          )

        %{
          "fuel" => fuel,
          "canal_fees" => Enum.count(route["passages"], &(&1 in ["panama", "suez"])) * 25_000,
          "duration_ms" => duration,
          "crew_estimate" => div(duration * class["crew"], 60_000),
          "route" => route
        }
    end
  end

  def voyage_quote(_ship, _destination, _catalogue), do: nil

  defp sail(state, account, id, destination, limit, catalogue) do
    with {:ok, ship, company, estimate} <-
           departure_check(state, account, id, destination, limit, catalogue) do
      owner = company["id"]

      ship = %{
        ship
        | "status" => "sailing",
          "destination" => destination,
          "depart_ms" => state.clock_ms,
          "arrive_ms" => state.clock_ms + estimate["duration_ms"],
          "fuel_total" => estimate["fuel"],
          "fuel_burned" => 0
      }

      ship = Map.put(ship, "voyage_speedup", @voyage_speedup)

      state =
        state
        |> put("ships", id, ship)
        |> put("companies", owner, %{
          company
          | "reserved" => company["reserved"] + estimate["fuel"],
            "cash" => company["cash"] - estimate["canal_fees"],
            "profit" => company["profit"] - estimate["canal_fees"]
        })

      state =
        Journal.post(
          state,
          owner,
          "departure",
          [
            {"cash_reserved", estimate["fuel"]},
            {"cash_available", -estimate["fuel"] - estimate["canal_fees"]},
            {"canal_expense", estimate["canal_fees"]}
          ],
          %{ship: id}
        )

      {:ok, state, %{"arrive_ms" => ship["arrive_ms"], "fuel" => estimate["fuel"]}}
    end
  end

  defp departure_check(state, account, id, destination, limit, catalogue) do
    ship = get(state, "ships", id)
    company = get(state, "companies", account["company_id"])

    cond do
      is_nil(ship) or is_nil(company) or ship["company_id"] != account["company_id"] ->
        {:error, :departure_ship_unavailable}

      ship["status"] != "docked" ->
        {:error,
         {:departure_busy, ship["status"],
          max(0, (ship["arrive_ms"] || state.clock_ms) - state.clock_ms)}}

      not is_binary(destination) or not Map.has_key?(catalogue["ports"], destination) ->
        {:error, :departure_destination_invalid}

      destination == ship["port"] ->
        {:error, {:departure_already_here, destination}}

      true ->
        case voyage_quote(ship, destination, catalogue) do
          nil -> {:error, {:departure_no_route, ship["port"], destination}}
          estimate -> departure_funding(ship, company, estimate, limit)
        end
    end
  end

  defp departure_funding(ship, company, estimate, limit) do
    available = company["cash"] - company["reserved"]
    required = estimate["fuel"] + estimate["canal_fees"]

    cond do
      not is_integer(limit) or limit < 0 ->
        {:error, :departure_fuel_limit_invalid}

      limit < estimate["fuel"] ->
        {:error, {:departure_fuel_limit, estimate["fuel"], limit}}

      estimate["duration_ms"] > 86_400_000 ->
        {:error, {:departure_too_long, estimate["duration_ms"]}}

      company["unpaid"] > 0 ->
        {:error, {:departure_unpaid, company["unpaid"]}}

      available < required ->
        {:error, {:departure_funds, estimate["fuel"], estimate["canal_fees"], available}}

      true ->
        {:ok, ship, company, estimate}
    end
  end

  # Older in-flight voyages used 60x. Preserve their progress when tuning changes;
  # the persisted multiplier prevents applying this adjustment on later ticks.
  defp retime_voyage(%{"status" => "sailing"} = ship, clock) do
    previous = Map.get(ship, "voyage_speedup", 60)

    if previous == @voyage_speedup do
      ship
    else
      ship
      |> Map.put(
        "depart_ms",
        clock - div((clock - ship["depart_ms"]) * previous, @voyage_speedup)
      )
      |> Map.put(
        "arrive_ms",
        clock + max(1, div((ship["arrive_ms"] - clock) * previous, @voyage_speedup))
      )
      |> Map.put("voyage_speedup", @voyage_speedup)
    end
  end

  defp retime_voyage(ship, _clock), do: ship

  defp validate_catalogue!(catalogue) do
    Enum.each(raw_goods(), fn good ->
      unless Map.has_key?(catalogue["goods"], good),
        do: raise(ArgumentError, "unknown raw production good: #{good}")
    end)

    Enum.each(catalogue["ports"], fn {port, definition} ->
      Enum.each(definition["roles"], fn {good, role} ->
        unless Map.has_key?(catalogue["goods"], good),
          do: raise(ArgumentError, "unknown role good at #{port}: #{good}")

        if catalogue["goods"][good]["shelf_ms"] > 0 and String.contains?(role, "/"),
          do: raise(ArgumentError, "perishable merchant markets are not supported")
      end)
    end)
  end

  def raw_goods,
    do: [
      "Iron ore",
      "Grain",
      "Lumber",
      "Crude oil",
      "Fruit",
      "Seafood",
      "Meat",
      "Scrap aluminium",
      "Copper scrap",
      "Recovered plastics"
    ]

  def advance(state, elapsed, catalogue) when is_integer(elapsed) and elapsed >= 0 do
    now = state.clock_ms + elapsed
    state = %{state | clock_ms: now}

    state =
      Enum.reduce(entities(state, "ships"), state, fn {id, ship}, state ->
        ship = retime_voyage(ship, now - elapsed)

        company =
          get(state, "companies", ship["company_id"]) ||
            raise(
              ArgumentError,
              "ship #{id} has no owning company; retire or transfer ships before removing a company"
            )

        class = classes()[ship["class"]]
        end_ms = ship["arrive_ms"] || now

        moving_ms =
          if ship["status"] == "sailing",
            do: max(0, min(now, end_ms) - ship["last_cost_ms"]),
            else: 0

        idle_ms = now - ship["last_cost_ms"] - moving_ms

        crew_numerator =
          ship["crew_remainder"] + moving_ms * class["crew"] * 2 + idle_ms * class["crew"]

        crew = div(crew_numerator, 120_000)

        fuel_burned =
          if ship["status"] == "sailing",
            do:
              max(
                ship["fuel_burned"],
                min(
                  ship["fuel_total"],
                  div(
                    ship["fuel_total"] * max(0, now - ship["depart_ms"]),
                    ship["arrive_ms"] - ship["depart_ms"]
                  )
                )
              ),
            else: ship["fuel_burned"]

        fuel = fuel_burned - ship["fuel_burned"]
        cash = company["cash"] - fuel
        reserved = company["reserved"] - fuel
        paid = min(crew, max(0, cash - reserved))

        {expired, cargo} =
          Enum.split_with(ship["cargo"], &(&1["expires_ms"] != nil and &1["expires_ms"] <= now))

        spoilage = Enum.sum(Enum.map(expired, &(&1["unit_cost"] * &1["quantity"])))

        company = %{
          company
          | "cash" => cash - paid,
            "reserved" => reserved,
            "unpaid" => company["unpaid"] + crew - paid,
            "profit" => company["profit"] - crew - fuel - spoilage
        }

        ship = %{
          ship
          | "fuel_burned" => fuel_burned,
            "last_cost_ms" => now,
            "crew_remainder" => rem(crew_numerator, 120_000),
            "cargo" => cargo
        }

        ship =
          if ship["status"] != "docked" and end_ms <= now do
            %{
              ship
              | "port" => ship["destination"] || ship["port"],
                "destination" => nil,
                "status" => "docked",
                "arrive_ms" => nil,
                "depart_ms" => nil
            }
          else
            ship
          end

        state
        |> put("ships", id, ship)
        |> put("companies", company["id"], company)
        |> Journal.post(
          company["id"],
          "operations",
          [
            {"fuel_expense", fuel},
            {"cash_reserved", -fuel},
            {"crew_expense", crew},
            {"cash_available", -paid},
            {"payables", -(crew - paid)},
            {"spoilage_expense", spoilage},
            {"inventory", -spoilage}
          ],
          %{ship: id}
        )
      end)

    state =
      Enum.reduce(entities(state, "markets"), state, fn {id, market}, state ->
        replenished = div(now - market["last_production"], @market_replenishment_ms)
        item = catalogue["goods"][market["good"]]
        batches = Enum.reject(market["batches"], &(&1["expires_ms"] <= now))

        stock =
          if item["shelf_ms"] > 0,
            do: Enum.sum(Enum.map(batches, & &1["quantity"])),
            else: market["stock"]

        market = %{market | "batches" => batches, "stock" => stock}
        state = put(state, "markets", id, market)

        if replenished > 0 do
          # Manufactured supply is a finite initial allocation until input purchasing
          # and recipes are implemented. Never synthesize re-export merchant stock.
          raw = market["good"] in raw_goods()

          produced =
            if raw and market["seller"] and not market["merchant"],
              do: min(max(0, 500 - stock), replenished),
              else: 0

          {state, batches} =
            if item["shelf_ms"] > 0 and produced > 0 do
              {next, lot} =
                CargoLots.create(state, market["good"], produced, now + item["shelf_ms"])

              {next, batches ++ [lot]}
            else
              {state, batches}
            end

          market = %{
            market
            | "stock" => stock + produced,
              "batches" => batches,
              "budget" =>
                min(
                  item["reference_cents"] * 1000,
                  market["budget"] +
                    if(market["buyer"], do: replenished * item["reference_cents"], else: 0)
                ),
              "demand" =>
                min(500, market["demand"] + if(market["buyer"], do: replenished, else: 0)),
              "last_production" =>
                market["last_production"] + replenished * @market_replenishment_ms
          }

          put(state, "markets", id, market)
        else
          state
        end
      end)

    Enum.reduce(entities(state, "invitations"), state, fn {id, invite}, state ->
      if invite["status"] == "issued" and invite["expires_ms"] <= now do
        state = put(state, "invitations", id, %{invite | "status" => "expired"})

        case get(state, "accounts", invite["inviter"]) do
          nil ->
            state

          account ->
            put(state, "accounts", account["id"], %{
              account
              | "invite_quota" => account["invite_quota"] + 1
            })
        end
      else
        state
      end
    end)
  end

  def public(state, catalogue) do
    %{
      "clock_ms" => state.clock_ms,
      "revision" => state.revision,
      "ports" => catalogue["ports"],
      "goods" => catalogue["goods"],
      "companies" =>
        Map.new(entities(state, "companies"), fn {id, c} ->
          {id, Map.take(c, ["id", "name", "home", "created_ms"])}
        end),
      "ships" =>
        Map.new(entities(state, "ships"), fn {id, s} ->
          {id,
           Map.take(s, [
             "id",
             "company_id",
             "name",
             "class",
             "port",
             "destination",
             "status",
             "depart_ms",
             "arrive_ms"
           ])}
        end)
    }
  end

  def private(state, account) do
    %{
      "account" => Map.drop(account, ["inviter"]),
      "company" => get(state, "companies", account["company_id"]),
      "ships" =>
        Map.filter(entities(state, "ships"), fn {_, s} ->
          s["company_id"] == account["company_id"]
        end),
      "notices" => Map.get(Map.get(state, :notices_by_account, %{}), account["id"], [])
    }
  end

  defp notice(state, nil, _id, _text), do: state

  defp notice(state, account, id, text) do
    state
    |> put("notices", id, %{
      "account_id" => account,
      "text" => text,
      "clock_ms" => state.clock_ms
    })
    |> prune_notices()
  end

  # Replace pending invitation notices with company announcements, including
  # notices persisted before this replacement rule was introduced.
  # Retain the newest 100 notices per account, including across restarts.
  defp prune_notices(state) do
    retained =
      entities(state, "notices")
      |> Enum.reject(fn
        {"accepted:" <> invitee_id, _notice} ->
          case get(state, "accounts", invitee_id) do
            %{"company_id" => company_id} when is_binary(company_id) ->
              get(state, "notices", "company:" <> company_id) != nil

            _ ->
              false
          end

        _ ->
          false
      end)
      |> Enum.group_by(fn {_, notice} -> notice["account_id"] end)
      |> Enum.flat_map(fn {_, notices} ->
        notices
        |> Enum.sort_by(fn {id, notice} -> {-notice["clock_ms"], id} end)
        |> Enum.take(100)
      end)
      |> Map.new()

    index =
      retained
      |> Map.values()
      |> Enum.group_by(& &1["account_id"])
      |> Map.new(fn {account, notices} ->
        {account, Enum.sort_by(notices, & &1["clock_ms"], :desc)}
      end)

    state
    |> Map.put(:entities, Map.put(state.entities, "notices", retained))
    |> Map.put(:notices_by_account, index)
  end

  defp handling_rate(%{"tiers" => %{"cost" => "high"}}), do: 600
  defp handling_rate(%{"tiers" => %{"cost" => "low"}}), do: 200
  defp handling_rate(_), do: 400
end
