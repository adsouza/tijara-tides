defmodule TijaraTides.Domain.ShipInstructions do
  @moduledoc "Private, single-visit cargo instructions; fills and progress settle in the same world transaction."
  import TijaraTides.Domain.State
  alias TijaraTides.Domain.{CargoRules, Fleet, Notices, Trade, Trading}

  @open ["planned", "waiting"]

  def add(state, account, params, context) do
    ship = get(state, "ships", params["ship"])
    catalogue = context.catalogue
    good = catalogue["goods"][params["good"]]
    port = params["port"]
    side = params["side"]
    quantity = params["quantity"]
    limit = params["limit"]
    budget = params["budget"]
    onward = params["onward"]

    cond do
      is_nil(ship) or is_nil(account["company_id"]) or ship["company_id"] != account["company_id"] ->
        {:error, :instruction_ship_not_owned}

      ship["status"] not in ["docked", "loading", "unloading", "sailing"] or
        is_nil(catalogue["ports"][port]) or port == ship["port"] or
          (ship["status"] == "sailing" and port != ship["destination"]) ->
        {:error, :instruction_destination_invalid}

      side not in ["buy", "sell"] or is_nil(good) or good["manual"] != true or
        not CargoRules.compatible_cargo?(ship, good) or
          is_nil(get(state, "markets", port <> "|" <> params["good"])) ->
        {:error, :instruction_cargo_invalid}

      not is_integer(quantity) or quantity < 1 or quantity > 10_000 or
        not is_integer(limit) or limit < 0 or limit > 1_000_000_000_000 ->
        {:error, :instruction_quantity_invalid}

      side == "sell" and
          quantity >
            Enum.sum(
              for batch <- ship["cargo"], batch["good"] == params["good"], do: batch["quantity"]
            ) ->
        {:error, :instruction_sell_exceeds_cargo}

      side == "sell" and
          Enum.any?(entities(state, "ship_instructions"), fn {_, order} ->
            order["ship_id"] == ship["id"] and order["good"] == params["good"] and
              order["side"] == "sell" and order["status"] in @open
          end) ->
        {:error, :instruction_duplicate_sell}

      side == "buy" and visit_onwards(state, ship["id"], port) not in [[], [onward]] ->
        {:error, :instruction_onward_conflict}

      side == "buy" and
          (not is_integer(budget) or budget < 1 or budget > 1_000_000_000_000 or
             is_nil(catalogue["ports"][onward]) or onward == port) ->
        {:error, :instruction_budget_invalid}

      Enum.count(entities(state, "ship_instructions"), fn {_, order} ->
        order["ship_id"] == ship["id"] and order["status"] in @open
      end) >= 20 ->
        {:error, :instruction_limit_reached}

      true ->
        order = %{
          "id" => context.id,
          "company_id" => ship["company_id"],
          "ship_id" => ship["id"],
          "port" => port,
          "good" => params["good"],
          "side" => side,
          "quantity" => quantity,
          "filled" => 0,
          "limit" => limit,
          "budget" => if(side == "buy", do: budget),
          "spent" => 0,
          "onward" => if(side == "buy", do: onward),
          "status" => "planned",
          "reason" => "Awaiting arrival and a berth",
          "created_ms" => state.clock_ms
        }

        state = if side == "buy", do: save_visit(state, ship, port, onward), else: state

        {:ok, put(state, "ship_instructions", order["id"], order),
         %{"instruction_id" => order["id"]}}
    end
  end

  def change_onward(state, account, ship_id, port, onward, catalogue, auto_depart \\ nil) do
    ship = get(state, "ships", ship_id)
    orders = visit_buys(state, ship_id, port)

    cond do
      is_nil(ship) or is_nil(account["company_id"]) or ship["company_id"] != account["company_id"] ->
        {:error, :instruction_ship_not_owned}

      is_nil(catalogue["ports"][port]) or
          (ship["status"] == "sailing" and port != ship["destination"]) ->
        {:error, :instruction_destination_invalid}

      auto_depart not in [nil, true, false] ->
        {:error, :instruction_auto_depart_invalid}

      is_nil(catalogue["ports"][onward]) or onward == port ->
        {:error, :instruction_onward_invalid}

      true ->
        changed =
          Enum.reduce(orders, state, fn order, state ->
            put(state, "ship_instructions", order["id"], %{order | "onward" => onward})
          end)

        changed = save_visit(changed, ship, port, onward, auto_depart)
        {:ok, changed, %{"onward" => onward}}
    end
  end

  defp visit_buys(state, ship_id, port) do
    entities(state, "ship_instructions")
    |> Map.values()
    |> Enum.filter(
      &(&1["ship_id"] == ship_id and &1["port"] == port and &1["side"] == "buy" and
          &1["status"] in @open)
    )
  end

  defp save_visit(state, ship, port, onward, auto_depart \\ nil) do
    id = ship["id"] <> "|" <> port
    previous = get(state, "visit_plans", id)

    enabled =
      if is_nil(auto_depart),
        do: previous != nil && previous["auto_depart"] == true,
        else: auto_depart

    put(state, "visit_plans", id, %{
      "id" => id,
      "ship_id" => ship["id"],
      "company_id" => ship["company_id"],
      "port" => port,
      "onward" => onward,
      "auto_depart" => enabled,
      "departure_wait" => nil
    })
  end

  defp visit_onwards(state, ship_id, port) do
    plan = get(state, "visit_plans", ship_id <> "|" <> port)

    visit_buys(state, ship_id, port)
    |> Enum.map(& &1["onward"])
    |> Kernel.++(if(plan, do: [plan["onward"]], else: []))
    |> Enum.uniq()
  end

  def cancel(state, account, id, catalogue) do
    company_id = account["company_id"]

    case get(state, "ship_instructions", id) do
      %{"company_id" => owner, "status" => status} = order
      when owner != nil and owner == company_id and status in @open ->
        {:ok, finish(state, order, "Cancelled by player", catalogue), %{"instruction_id" => id}}

      _ ->
        {:error, :instruction_not_active}
    end
  end

  # Called only after departure succeeds. Never carry a waiting remainder into
  # another visit, or keep a plan for a destination the ship sailed away from.
  def depart(state, ship_id, destination, catalogue) do
    state =
      Enum.reduce(entities(state, "visit_plans"), state, fn {id, plan}, state ->
        if plan["ship_id"] == ship_id and plan["port"] != destination,
          do: delete(state, "visit_plans", id),
          else: state
      end)

    Enum.reduce(entities(state, "ship_instructions"), state, fn {_, order}, state ->
      if order["ship_id"] == ship_id and order["status"] in @open and
           (order["status"] == "waiting" or order["port"] != destination),
         do: finish(state, order, "Cancelled remainder on departure", catalogue),
         else: state
    end)
  end

  def advance(state, catalogue) do
    # Stable order across restarts; sell instructions always precede purchases.
    entities(state, "ship_instructions")
    |> Map.values()
    |> Enum.filter(&(&1["status"] in @open))
    |> Enum.sort_by(&{if(&1["side"] == "sell", do: 0, else: 1), &1["created_ms"], &1["id"]})
    |> Enum.reduce(state, &attempt(&2, &1, catalogue))
    |> depart_ready_visits(catalogue)
  end

  defp depart_ready_visits(state, catalogue) do
    entities(state, "visit_plans")
    |> Enum.sort_by(fn {id, _} -> id end)
    |> Enum.reduce(state, fn {id, plan}, state ->
      ship = get(state, "ships", plan["ship_id"])

      if plan["auto_depart"] == true and not is_nil(ship) and ship["port"] == plan["port"] and
           ship["status"] in ["docked", "loading", "unloading"] do
        pending =
          Enum.any?(entities(state, "ship_instructions"), fn {_, order} ->
            order["ship_id"] == ship["id"] and order["port"] == plan["port"] and
              order["status"] in @open
          end)

        cond do
          ship["status"] != "docked" ->
            departure_wait(state, plan, "Waiting for cargo handling to finish")

          pending ->
            departure_wait(state, plan, "Waiting for cargo orders to be filled or cancelled")

          true ->
            company = get(state, "companies", ship["company_id"])
            account = get(state, "accounts", company["account_id"])
            quote = Fleet.voyage_quote(ship, plan["onward"], catalogue)

            case Fleet.sail(
                   state,
                   account,
                   ship["id"],
                   plan["onward"],
                   if(quote, do: quote["fuel"], else: 0),
                   catalogue
                 ) do
              {:ok, changed, _} ->
                Notices.notice(
                  changed,
                  account["id"],
                  "auto-depart:" <> id,
                  "#{ship["name"]} automatically departed #{plan["port"]} for #{plan["onward"]}."
                )

              {:error, reason} ->
                departure_wait(state, plan, departure_reason(reason))
            end
        end
      else
        state
      end
    end)
  end

  defp departure_wait(state, plan, reason) do
    if plan["departure_wait"] == reason do
      state
    else
      ship = get(state, "ships", plan["ship_id"])
      company = get(state, "companies", ship["company_id"])

      state
      |> put("visit_plans", plan["id"], Map.put(plan, "departure_wait", reason))
      |> Notices.notice(
        company["account_id"],
        "auto-depart:" <> plan["id"],
        "#{ship["name"]}: automatic departure to #{plan["onward"]} paused. #{reason}."
      )
    end
  end

  defp departure_reason({:departure_funds, _, _, _}),
    do: "Waiting for available funds for fuel and canal fees"

  defp departure_reason({:departure_unpaid, _}), do: "Waiting for unpaid operating costs to clear"

  defp departure_reason({:departure_no_route, _, _}),
    do: "No sea route is available to the onward destination"

  defp departure_reason({:departure_too_long, _}),
    do: "The onward voyage exceeds the maximum duration"

  defp departure_reason(_), do: "The onward destination is unavailable; update the visit plan"

  defp attempt(state, order, catalogue) do
    ship = get(state, "ships", order["ship_id"])

    if ship && ship["status"] == "docked" && ship["port"] == order["port"] do
      company = get(state, "companies", order["company_id"])
      account = get(state, "accounts", company["account_id"])
      remaining = order["quantity"] - order["filled"]

      trade = %Trade{
        side: order["side"],
        ship_id: ship["id"],
        good: order["good"],
        quantity: 1,
        limit: order["limit"],
        destination: order["onward"]
      }

      # Pure probes are discarded. Only the final successful fill is committed.
      result = fn quantity ->
        case Trading.execute(state, account, %{trade | quantity: quantity}, catalogue) do
          {:ok, changed, reply} ->
            if order["side"] == "buy" and order["spent"] + reply["spent"] > order["budget"],
              do: {:error, :instruction_budget_exhausted},
              else: {:ok, changed, reply}

          error ->
            error
        end
      end

      first =
        if length(visit_onwards(state, ship["id"], order["port"])) > 1 and order["side"] == "buy",
          do: {:error, :instruction_onward_conflict},
          else: result.(1)

      case first do
        {:error, :capacity_exceeded} ->
          sales_pending =
            Enum.any?(entities(state, "ship_instructions"), fn {_, other} ->
              other["ship_id"] == order["ship_id"] and other["port"] == order["port"] and
                other["side"] == "sell" and other["status"] in @open
            end)

          plan = get(state, "visit_plans", ship["id"] <> "|" <> order["port"])

          if sales_pending or (plan && plan["auto_depart"] == true),
            do:
              wait(
                state,
                order,
                "Waiting for hold capacity; fill or cancel remaining orders",
                catalogue
              ),
            else:
              finish(
                state,
                order,
                "Hold capacity exhausted; cancelled unfilled remainder",
                catalogue
              )

        {:error, reason} ->
          wait(state, order, reason_text(reason), catalogue)

        {:ok, _, _} ->
          quantity = maximum(1, remaining, result)
          {:ok, changed, reply} = result.(quantity)
          filled = order["filled"] + quantity

          order = %{
            order
            | "filled" => filled,
              "spent" => order["spent"] + (reply["spent"] || 0),
              "status" => if(filled == order["quantity"], do: "filled", else: "waiting"),
              "reason" =>
                if(filled == order["quantity"],
                  do: "Target filled",
                  else: "Waiting for handling to finish"
                )
          }

          update(changed, order, catalogue)
      end
    else
      if ship && ship["port"] == order["port"] && ship["status"] in ["loading", "unloading"],
        do: wait(state, order, "Waiting for handling to finish", catalogue),
        else: state
    end
  end

  defp maximum(low, high, _result) when low == high, do: low

  defp maximum(low, high, result) do
    mid = div(low + high + 1, 2)

    case result.(mid) do
      {:ok, _, _} -> maximum(mid, high, result)
      {:error, _} -> maximum(low, mid - 1, result)
    end
  end

  defp wait(state, order, reason, catalogue),
    do: update(state, %{order | "status" => "waiting", "reason" => reason}, catalogue)

  defp finish(state, order, reason, catalogue),
    do: update(state, %{order | "status" => "cancelled", "reason" => reason}, catalogue)

  defp update(state, order, catalogue) do
    previous = get(state, "ship_instructions", order["id"])

    if previous == order do
      state
    else
      company = get(state, "companies", order["company_id"])
      ship = get(state, "ships", order["ship_id"])

      state
      |> put("ship_instructions", order["id"], order)
      |> Notices.notice(
        company["account_id"],
        "instruction:" <> order["id"],
        "#{ship["name"]} at #{order["port"]}: #{order["side"]} #{catalogue["goods"][order["good"]]["name"]}, #{order["filled"]}/#{order["quantity"]} lots filled. #{order["reason"]}."
      )
    end
  end

  defp reason_text(:instruction_onward_conflict),
    do: "Choose one shared onward port for this visit before purchases can resume"

  defp reason_text(:price_changed), do: "Waiting for the limit price"
  defp reason_text(:insufficient_cargo), do: "Waiting for cargo aboard"
  defp reason_text(:insufficient_supply), do: "Waiting for market supply"
  defp reason_text(:insufficient_demand), do: "Waiting for market demand or buyer funds"

  defp reason_text(:insufficient_cash),
    do: "Waiting for available company funds or unpaid costs to clear"

  defp reason_text(:instruction_budget_exhausted), do: "Purchase spending cap exhausted"

  defp reason_text({:purchase_voyage_funds, _, _, _}),
    do: "Waiting for funds after preserving onward voyage costs"

  defp reason_text(:purchase_destination_required), do: "Onward voyage is unavailable"
  defp reason_text(_), do: "Cargo is currently unavailable for trading at this port"
end
